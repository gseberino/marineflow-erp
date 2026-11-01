-- Agenda de Produção, Fase 7, etapa 7c ("quem sabe fazer o quê"), pacote P3: a violação do publicado e a escada da revisão. Com a 7c
-- ligada, o meio-dia publicado cuja equipe não tem quem o serviço pede deixa de poder acontecer (a violação habilidade: a vigia
-- replaneja, como a falta da equipe), e a escada da revisão diária da 7a nunca põe sozinho quem nunca vai sozinho nem deixa o
-- meio-dia de risco sem quem ele pede.
-- Spec: scratchpad agenda-pesquisa/spec-fase7c.md (§R5.3-2, §R5.4, §R5.5 item 3, §R5.7-1/-3, §R5.10-1, §3.1-6, §3.5, §5.3, §8.3
-- agenda_fase7c_violacao.sql); nomes: fase7-registro.md §1 e §2 (_agenda_violacoes: 20261029100900 → 7c P3; _agenda_gestor_reparo: 7a P9
-- → 7b correção 3 20261101100860 → 7c P3); respostas do dono: fase7-padroes.md (AG7-03 "ajudante = nunca sozinho em tarefa de risco";
-- AG7-10 "sem etiqueta = pode tudo, menos comissionar, que fica com o dono").
-- Depende das Fases 1 a 6, do lote de 30/10, da 7a e da 7b inteiras (as correções 100800, 100850 e 100860) e da 7c P1 e P2
-- (20261102100000: agenda_habilidades, os_exigencias, _agenda_atende, _agenda_meios_sem_quem_pede, os 3 interruptores e a lista
-- cancelada_motivo com habilidade; 20261102100100: o motor que replaneja com os filtros da 7c e o texto do cancelar habilidade).
--
-- ═══ DDL — OK NOMEADO ═══ (2 funções recriadas com as mesmas assinaturas; nenhuma tabela, coluna, lista, gatilho, job ou dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7c/p3/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (conferida a cada montagem: o
-- montador para se outra migration anterior a esta a definir depois da origem) — _agenda_violacoes de
-- 20261029100900_agenda_fase6_correcao_calculo.sql (o lote, a 7a e a 7b não a recriaram); _agenda_gestor_reparo de
-- 20261101100860_agenda_fase77b_correcao3.sql (a correção 3 da 7b, que a recriou de 20261031100750) —, e as mudanças estão só em
-- blocos "-- FASE 7c: … -- FASE 7c: fim" INSERIDOS e, dentro do bloco "-- FASE 7b: (correção 3)" da escada, numa marca de dentro
-- "-- (7c P3 …) … -- (7c: fim)" (a regra do R5.4 item 2; só acréscimo: nenhuma linha de antes é trocada). Tirados os blocos e a marca,
-- o corpo é o da origem, byte a byte (o montador e o V7/V9 de supabase/tests/agenda_fase7c_violacao.sql conferem).
--
-- POR QUE: com a 7c ligada, o motor escolhe quem vai pelo que cada um sabe fazer (P2), mas o que já está publicado só muda por
-- violação (§3.1-6): sem a violação habilidade, um meio-dia publicado antes (ou pela escada) com o ajudante sozinho no último dia do
-- banco de lítio ficaria como está. E a escada da revisão diária da 7a (ligada ter 03/11) põe no degrau 1 "outra pessoa livre no
-- mesmo dia e turno" e grava direto: a correção 3 da 7b já tira quem nunca vai sozinho pela régua da 7b (com a dupla fora de
-- desligado); com a 7c ligada, a régua passa a ser a da 7c (o papel novo de agenda_habilidades: também o dia fixo sem diária) e o
-- meio-dia passa a precisar de quem o serviço pede (R5.3-2, R5.10-1).
--
-- O QUE MUDA:
--   1. _agenda_violacoes: com modo_habilidade ligado, a alocação de turno, fora da reserva, de um meio-dia publicado cuja equipe não
--      tem quem o serviço pede (_agenda_meios_sem_quem_pede: a regra única _agenda_atende com a máscara do meio-dia — o que a OS pede em
--      todos e, no último meio-dia, o do último, menos quando o fechamento do dono naquele dia cobre) vira violação habilidade, logo
--      depois do "fixado pelo dono não sai" (a palavra do dono vale: o fixado e a equipe dita, que _agenda_meios_sem_quem_pede pula, não
--      violam). O resto do meio-dia e os meios-dias publicados da OS depois do congelado saem juntos (replanejado), como em toda
--      violação; no congelado, é evento real. A vigia replaneja (agenda_replanejar → o motor, com os filtros da 7c; a escada não
--      conserta violação habilidade: "outro_motivo") e o cancelar diz "a equipe do dia não tinha quem o serviço pede" (7c P2).
--   2. _agenda_gestor_reparo (a escada): com modo_habilidade ligado, (i) e (ii) do R5.3-2 numa conta só — a equipe do meio-dia depois
--      da troca (quem fica de turno na OS ali, os consertos já aceitos ali e o candidato) passa em _agenda_atende com a máscara do
--      meio-dia: o novo (papel 2 de agenda_habilidades, em p_hoje) só entra no meio-dia que fica com um responsável com instala >=
--      habilidade_nivel_par ou com o dono no turno (nos degraus 2 e 3 a OS não tem meio-dia ali: ele iria sozinho, e não entra), e o
--      ajudante sozinho não entra no meio-dia de risco. A régua da 7b (o bloco da correção 3, com a dupla fora de desligado) dá lugar à
--      da 7c (a marca de dentro). Só tira candidato: sem nenhum, a escada não conserta a OS (tudo ou nada) e o motor replaneja.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7c_violacao.sql; registradas em notas-fase77c.md, P3):
--   · a violação só é julgada com a porta de os_exigencias aberta (o service_role sem login ou o admin/financeiro logado) e por quem
--     pode chamar _agenda_meios_sem_quem_pede (sem grant: o motor, a vigia e a escada chegam como definer). A técnica logada que marca
--     pela tela (agenda_marcar_os → agenda_propor) e o service_role que chama _agenda_violacoes direto (ela tem o grant dele) recebiam
--     o 42501 no meio do caminho; para eles não há violação habilidade (a vigia, a cada 15 minutos, julga o publicado). Na escada, para
--     a técnica, a OS não pede ninguém em especial (como no motor, 7c P2 desvio 9) e só vale o novo nunca sozinho. A avaliação roda num
--     comando próprio, antes da consulta das violações, e não como um CTE dela: a permissão de uma função é conferida quando a consulta
--     que a cita começa, mesmo com o filtro que a pula, e o service_role direto quebraria também com a 7c desligada;
--   · a escada ganha a conferência do último meio-dia que a OS fica tendo (com modo_habilidade ligado): um degrau 2 ou 3 pode tirar o
--     último meio-dia do lugar e deixar como último um que ficou, cuja equipe não tem o que o último pede; aí a escada não conserta a
--     OS (sobrou tudo) e o motor replaneja. Só tira conserto. O meio-dia do candidato é "o último" quando nenhum outro meio-dia de turno
--     da OS (os que ficam, os que ainda vão ser consertados, no lugar de hoje, e os consertos aceitos) vem depois dele;
--   · na escada, a régua da 7c vale também para a OS com a equipe dita pelo dono (a pessoa dita é a que saiu; quem entra é escolha da
--     escada, não do dono), como a régua da 7b já valia.
--
-- O QUE NÃO MUDA: com modo_habilidade fora de ligado (desligado ou em teste), as duas funções são as de antes, byte a byte (a violação,
-- as Fases 1–6, a 7a e a 7b; a escada da correção 3 da 7b com a dupla fora de desligado). Nenhuma mensagem nova, nenhuma escrita nova.
-- Não há violação de responsável (§3.8 d5): o publicado sem o responsável só aparece na conferência da rodada (P5) e na medida.
--
-- ORDEM DE LIGAR: nada a ligar aqui (modo_habilidade é do P1; a migration de dado 20261102100600 o põe em sombra; o ligar é
-- modo_habilidade = ligado, com o OK nomeado do dono, spec §10; ao ligar, uma onda de replano do que já está publicado: a rede K da 7a
-- segura — §9, riscos do P3). PROVA: supabase/tests/agenda_fase7c_violacao.sql na bancada (node scripts/bancada-agenda/rodar.mjs).
-- APLICAR: só pelo roteiro de publicação da 7c, depois da 20261102100100 e antes da 20261102100300.
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.
--
-- DESFAZER: recriar _agenda_violacoes com o corpo de 20261029100900 e _agenda_gestor_reparo com o de 20261101100860 (as portas não
-- mudam). Quem recriar depois uma destas copia DESTA migration (R5.4 item 3; o 7d P4 copia _agenda_violacoes daqui).

-- ── 1. A violação do publicado ───────────────────────────────────────────────────────────────────────────────────

-- _agenda_violacoes (de 20261029100900_agenda_fase6_correcao_calculo.sql)
create or replace function public._agenda_violacoes(p_escopo uuid[], p_cart uuid[], p_semana boolean, p_info jsonb,
                                                    p_hoje date, p_cong date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ate   date;
  v_login uuid;
  v_res   jsonb;
  -- FASE 3 (C1): a falta da equipe (NOVO-agenda-27; quem replaneja pelo "não vou" ou pelo silêncio põe
  -- agenda.replano_da_falta = on na transação)
  v_falta boolean := coalesce(current_setting('agenda.replano_da_falta', true), '') = 'on';
  -- FASE 3 (C1): fim
  -- FASE 7c: (7c P3, §5.3) a violação habilidade: a equipe do meio-dia publicado não tem quem o serviço pede (só com modo_habilidade
  -- ligado e a porta de os_exigencias aberta, abaixo); os meios-dias em que falta alguém (os, dia, turno)
  v_hab   boolean := (public._agenda_cfg()).modo_habilidade = 'ligado';
  v_hab_m jsonb := '[]'::jsonb;
  -- FASE 7c: fim
begin
  select max(a.dia) into v_ate
    from public.agenda_alocacoes a
   where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
     and (a.service_order_id = any (p_escopo) or (p_semana and not (a.service_order_id = any (p_cart))));
  if v_ate is null then
    return '[]'::jsonb;
  end if;
  select py.app_user_id into v_login from public.payees py where py.id = public._agenda_dono(null);

  -- FASE 7c: (7c P3) o que a OS pede só é lido com a porta de os_exigencias aberta — o service_role sem login ou o admin/financeiro
  -- logado — e por quem pode chamar a avaliação do publicado (_agenda_meios_sem_quem_pede, sem grant: o motor, a vigia e a escada, que
  -- são definer, chegam aqui com os privilégios do dono das funções). A técnica logada que marca pela tela (agenda_marcar_os →
  -- agenda_propor) chega aqui e receberia o 42501 de os_exigencias no meio do motor; o service_role que chama esta função direto (ela
  -- tem o grant dele) receberia o 42501 da avaliação. Para esses, não há violação habilidade: a vigia, que roda a cada 15 minutos
  -- como definer, julga o publicado. A avaliação (_agenda_meios_sem_quem_pede: a regra _agenda_atende com a máscara do meio-dia — o
  -- que a OS pede em todos e, no último meio-dia, o do último, menos quando o fechamento do dono naquele dia cobre; pula as OS com a
  -- equipe dita pelo dono) roda aqui, fora da consulta de baixo: a função entra no plano só quando é chamada (a permissão de uma
  -- função é conferida quando a consulta que a cita começa, mesmo que um filtro a pule).
  if v_hab then
    begin
      v_hab := case when auth.uid() is not null then public.is_admin_or_financial(auth.uid())
                    else coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') in ('', 'service_role') end
               and has_function_privilege('public._agenda_meios_sem_quem_pede(date, date, date, uuid[], boolean)', 'execute');
    exception when others then
      v_hab := false;
    end;
  end if;
  if v_hab then
    select coalesce(jsonb_agg(jsonb_build_object('os', h.os, 'dia', h.dia, 'turno', h.turno)), '[]'::jsonb) into v_hab_m
      from public._agenda_meios_sem_quem_pede(p_hoje, v_ate, p_hoje, p_escopo) h;
  end if;
  -- FASE 7c: fim
  with
  alvo as (
    select a.*, a.dia <= p_cong as congelado
      from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
       and (a.service_order_id = any (p_escopo) or (p_semana and not (a.service_order_id = any (p_cart))))
  ),
  cap as (select * from public.agenda_capacidade(p_hoje, v_ate, p_hoje)),
  -- FASE 7c: (7c P3, §5.3) os meios-dias publicados cuja equipe não tem quem o serviço pede (a avaliação de cima; vazia fora de
  -- ligado ou com a porta fechada)
  hab as (select (h ->> 'os')::uuid as os, (h ->> 'dia')::date as dia, h ->> 'turno' as turno from jsonb_array_elements(v_hab_m) h),
  -- FASE 7c: fim
  av as (
    select a.*,
           case
             when not (a.service_order_id = any (p_cart)) then 'os_saiu'
             when so.status = 'awaiting_client' then 'cliente'
             when (p_info -> a.service_order_id::text -> 'pront' ->> 'estado') in ('concluida', 'fora_da_carteira') then 'os_saiu'
             -- a espera que o dono pôs ("deixa parada até sexta") só tira os dias DENTRO dela; o que vem depois fica
             when (p_info -> a.service_order_id::text -> 'pront' ->> 'estado') = 'congelada' and a.dia <= pl.congelada_ate then 'espera'
             when not py.active then 'pessoa'
             when a.presenca = 'turno' and k.situacao is distinct from 'livre' then 'pessoa'
             when a.presenca <> 'turno'
                  and (k.situacao is null or k.situacao in ('indisponivel', 'feriado', 'fim_de_semana') or not public.agenda_dia_util(a.dia)
                       or exists (select 1 from public.agenda_tasks t
                                   where t.kind = 'appointment' and v_login is not null and t.assignee_user_id = v_login
                                     and t.status not in ('cancelled', 'done') and t.scheduled_start_at is not null
                                     and tstzrange(t.scheduled_start_at, coalesce(t.scheduled_end_at, t.scheduled_start_at), '[]') && a.periodo))
               then 'pessoa'
             when a.fixado_por = 'dono' then null
             -- FASE 7c: (7c P3, §5.3) a equipe do meio-dia não tem quem o serviço pede (só ligado; a equipe dita pelo dono não entra
             -- em hab, e o fixado pelo dono já ficou acima): o resto do meio-dia sai junto (mesmo_meio) e o motor replaneja com os
             -- filtros da 7c
             when v_hab and a.tipo <> 'reserva' and a.presenca = 'turno'
                  and exists (select 1 from hab h where h.os = a.service_order_id and h.dia = a.dia and h.turno = a.turno)
               then 'habilidade'
             -- FASE 7c: fim
             when coalesce(pl.bem_indisponivel @> a.dia, false) then 'cliente'
             -- CORREÇÃO FASE 6: (C1) item 1: o que JÁ está publicado é julgado pelo início pelo material do dia DITO
             -- (os_prontidao.material.inicio_mat_dito, que só existe quando a data provável do aprendizado muda o início): o
             -- dia que só cairia pela data provável fica (o publicado só muda com evento real; o confirmado pelo cliente
             -- também). Segue a regra de baixo sem o material: o "não antes de" do cliente.
             when a.tipo <> 'reserva'
                  and coalesce(p_info -> a.service_order_id::text -> 'pront' #>> '{material,estado}', '') not in ('atrasado', 'sem_previsao')
                  and a.dia < (p_info -> a.service_order_id::text -> 'pront' #>> '{material,inicio_mat}')::date
                  and a.dia >= (p_info -> a.service_order_id::text -> 'pront' #>> '{material,inicio_mat_dito}')::date
               then case when a.dia < pl.nao_antes_de then 'cliente' end
             -- CORREÇÃO FASE 6: fim
             when a.tipo <> 'reserva'
                  and ((p_info -> a.service_order_id::text -> 'pront' #>> '{material,estado}') in ('atrasado', 'sem_previsao')
                       or a.dia < (p_info -> a.service_order_id::text -> 'pront' #>> '{material,inicio_mat}')::date) then 'material'
             when a.tipo <> 'reserva' and a.dia < pl.nao_antes_de then 'cliente'
             when a.tipo = 'reserva' and a.reserva_de = 'condicionada' and a.condicao_ate < p_hoje
                  and (public._agenda_classe_da_os(p_info -> a.service_order_id::text -> 'pront',
                                                   p_info -> a.service_order_id::text -> 'meios', p_hoje) ->> 'classe')::int not in (1, 2)
               then 'condicao_vencida'
           end as por_que
      from alvo a
      join public.service_orders so on so.id = a.service_order_id
      join public.payees py on py.id = a.payee_id
      left join public.os_planejamento pl on pl.service_order_id = a.service_order_id
      left join cap k on k.payee_id = a.payee_id and k.dia = a.dia and k.turno = a.turno
  ),
  violadas as (select * from av where av.por_que is not null),
  -- (a espera não replaneja o depois: os dias que caem depois dela ficam como estão, e o que faltar o motor completa
  -- depois do último dia marcado, quando a espera acabar)
  os_v as (select v.service_order_id, bool_or(v.tipo <> 'reserva') as comp from violadas v where v.por_que <> 'espera' group by 1),
  mesmo_meio as (
    select av.* from av
     where av.por_que is null and av.tipo <> 'reserva' and av.fixado_por is distinct from 'dono'
       and exists (select 1 from violadas v where v.service_order_id = av.service_order_id and v.dia = av.dia
                                             and v.turno = av.turno and v.tipo <> 'reserva')
  ),
  depois as (
    select av.* from av join os_v on os_v.service_order_id = av.service_order_id and os_v.comp
     where av.por_que is null and av.tipo <> 'reserva' and av.estado = 'publicada' and av.dia > p_cong
  ),
  -- FASE 3 (C1): a falta é evento real (decisões de 23/10: hoje e amanhã congelados SALVO evento real) — o que a OS tinha
  -- publicado depois de hoje e dentro do congelado (amanhã) sai junto, para os meios-dias que sobram voltarem num bloco só
  -- (sem isso o dia de amanhã ficava e o resto ia para depois: 2 interrupções). O desfazer do replano volta tudo.
  depois_da_falta as (
    select av.* from av join os_v on os_v.service_order_id = av.service_order_id and os_v.comp
     where v_falta and av.por_que is null and av.tipo <> 'reserva' and av.estado = 'publicada'
       and av.dia > p_hoje and av.dia <= p_cong
  ),
  -- FASE 3 (C1): fim
  tudo as (
    select v.id, v.service_order_id, v.por_que, true as violada, v.congelado, v.tipo, v.estado, v.fixado_por, v.reserva_de,
           v.payee_id, v.dia, v.turno, v.presenca from violadas v
    union
    select m.id, m.service_order_id, 'replanejado', false, m.congelado, m.tipo, m.estado, m.fixado_por, m.reserva_de,
           m.payee_id, m.dia, m.turno, m.presenca from mesmo_meio m
    union
    select d.id, d.service_order_id, 'replanejado', false, d.congelado, d.tipo, d.estado, d.fixado_por, d.reserva_de,
           d.payee_id, d.dia, d.turno, d.presenca from depois d
  -- FASE 3 (C1): o que a falta solta do congelado
    union
    select f.id, f.service_order_id, 'replanejado', false, f.congelado, f.tipo, f.estado, f.fixado_por, f.reserva_de,
           f.payee_id, f.dia, f.turno, f.presenca from depois_da_falta f
  -- FASE 3 (C1): fim
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'alocacao_id', t.id, 'os', t.service_order_id, 'motivo', t.por_que, 'violada', t.violada, 'congelado', t.congelado,
           'tipo', t.tipo, 'estado', t.estado, 'fixado_por', t.fixado_por, 'reserva_de', t.reserva_de,
           'payee_id', t.payee_id, 'dia', t.dia, 'turno', t.turno, 'presenca', t.presenca)
           order by t.service_order_id, t.dia, t.turno = 'tarde', t.payee_id, t.id), '[]'::jsonb)
    into v_res
    from tudo t;
  return v_res;
end;
$function$;

comment on function public._agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date) is
  'Agenda de Produção (Fase 2, P2; Fase 3, revisão C1): a etapa da estabilidade — cada alocação vigente de hoje em diante, sem resultado, das OS do escopo (e, na semana, das que saíram da carteira) que não pode mais acontecer: a OS saiu da carteira, está esperando o cliente ou concluída (os_saiu/cliente); o dia dentro da espera que o dono pôs (espera: só até congelada_ate, o depois fica); a pessoa não está mais livre ou a ponta do dono ficou ocupada por compromisso com hora (pessoa); o bem fora ou o "não antes de" (cliente); o material atrasado, sem previsão ou chegando depois do dia (material); a reserva condicionada vencida sem a condição (condicao_vencida). O fixado pelo dono só pelas três primeiras (a espera é dele também). Junto vão o resto do meio-dia quebrado e os meios-dias publicados da OS depois do congelado (replanejado); com agenda.replano_da_falta = on (a falta da equipe, NOVO-agenda-27), também os publicados de depois de hoje dentro do congelado. [{alocacao_id, os, motivo, violada, congelado, tipo, estado, fixado_por, reserva_de, payee_id, dia, turno, presenca}]. CORREÇÃO FASE 6 (C1, item 1): o material julga o que já está publicado pelo início do dia DITO (material.inicio_mat_dito da prontidão, quando a data provável do aprendizado o muda): o dia que só cairia pela data provável não sai (nem o confirmado pelo cliente). FASE 7c (P3, §5.3): com modo_habilidade ligado, a alocação de turno, fora da reserva, do meio-dia publicado cuja equipe não tem quem o serviço pede (_agenda_meios_sem_quem_pede: a regra única _agenda_atende com a máscara do meio-dia; pula as OS com a equipe dita pelo dono) vira habilidade, logo depois do fixado pelo dono (que não sai); o resto do meio-dia e o depois do congelado saem juntos (replanejado), como em toda violação. Só com a porta de os_exigencias aberta (o service_role sem login ou o admin/financeiro logado) e para quem pode chamar a avaliação (os definer da agenda): a técnica logada que marca pela tela e o service_role direto não veem a violação habilidade (a vigia julga). Fora de ligado, a de antes, byte a byte.';

-- ── 2. A escada da revisão ───────────────────────────────────────────────────────────────────────────────────────

-- _agenda_gestor_reparo (de 20261101100860_agenda_fase77b_correcao3.sql)
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
  -- FASE 7c: (7c P3, R5.3-2) o que cada pessoa faz (agenda_habilidades em p_hoje) e o que a OS pede (os_exigencias), uma leitura só,
  -- com modo_habilidade ligado; e a falta do último meio-dia que a OS fica tendo (a conferência do fim)
  v_7c_hab   jsonb := '{}'::jsonb;
  v_7c_n     jsonb;
  v_7c_le    boolean;
  v_7c_exg   jsonb;
  v_7c_ext   int := 0;
  v_7c_exu   int := 0;
  v_7c_dalt  int;
  v_7c_falta text;
  -- FASE 7c: fim
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
  -- FASE 7c: (7c P3, R5.3-2) com modo_habilidade ligado, a escada usa a régua da 7c: o que cada pessoa faz (agenda_habilidades em
  -- p_hoje, o dia em que a 7c mede o papel: quem a grade das semanas da escada tem, quem está na OS e o dono) e o que a OS pede
  -- (os_exigencias) — este só com a porta dela aberta (o service_role sem login ou o admin/financeiro logado; para a técnica logada, a
  -- OS não pede ninguém em especial, como no motor, e só vale o novo nunca sozinho)
  if cf.modo_habilidade = 'ligado' then
    v_7c_n := jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                                 'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura, 'par', cf.habilidade_nivel_par);
    begin
      v_7c_le := case when auth.uid() is not null then public.is_admin_or_financial(auth.uid())
                      else coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') in ('', 'service_role') end;
    exception when others then
      v_7c_le := false;
    end;
    if v_7c_le then
      v_7c_exg := public.os_exigencias(p_os, p_hoje);
      v_7c_ext := coalesce((v_7c_exg ->> 'todos')::int, 0);
      v_7c_exu := coalesce((v_7c_exg ->> 'ultimo')::int, 0);
    end if;
    select coalesce(jsonb_object_agg(h.payee_id::text, jsonb_build_array(h.instala, h.comissiona, h.altura, h.papel)), '{}'::jsonb),
           max(h.altura) filter (where h.eh_dono)
      into v_7c_hab, v_7c_dalt
      from public.agenda_habilidades(p_hoje, array(
             select u.p from (select (c ->> 'payee_id')::uuid as p from jsonb_array_elements(v_cap) c
                              union
                              select a.payee_id from public.agenda_alocacoes a
                               where a.service_order_id = p_os and a.estado in ('publicada', 'fixada')
                              union
                              select v_dono) u
              where u.p is not null order by 1)) h;
  end if;
  -- FASE 7c: fim
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
         -- FASE 7b: (correção 3) quem nunca fica sozinho (a regra do motor da 7b, com modo_dupla fora de desligado: o novato,
         -- com novato_sozinho falso, e quem vem sob demanda, com sob_demanda_sozinho falso) só entra no degrau 1 e só no meio-dia que fica
         -- com outra pessoa de turno da OS que pode ficar sozinha (fora as que saem) ou com o dono no turno; nunca nos degraus 2 e 3 (lá ele
         -- iria sozinho: a OS não tem meio-dia ali). Sem isso, a falta do Alex num meio-dia com o Mateus dito livre punha o Mateus sozinho
         -- (o validador não confere companhia). Só tira candidato: sem nenhum, a escada não conserta a OS (tudo ou nada) e o motor
         -- replaneja com a regra dele. Com modo_dupla desligado, ou com quem pode ficar sozinho, a escada de antes, byte a byte.
         and (cf.modo_dupla = 'desligado'
              -- (7c P3, R5.3-2) com modo_habilidade ligado, a régua de quem nunca fica sozinho é a da 7c (o bloco "-- FASE 7c:" logo
              -- abaixo: o papel novo de agenda_habilidades no lugar do novato e de quem vem sob demanda da 7b; uma régua só, a do motor
              -- com a 7c ligada, §R2)
              or cf.modo_habilidade = 'ligado'
              -- (7c: fim)
              or not ((not cf.novato_sozinho and public._agenda_e_novato(k.payee_id, a.dia))
                       or (not cf.sob_demanda_sozinho and public._agenda_e_sob_demanda(k.payee_id, a.dia)))
              or (a.grau = 1
                  and (exists (select 1 from public.agenda_alocacoes x
                                where x.service_order_id = p_os and x.estado in ('publicada', 'fixada') and x.tipo <> 'reserva'
                                  and x.dia = a.dia and x.turno = a.turno and x.presenca = 'turno' and not (x.id = any (v_ids))
                                  and (x.payee_id is not distinct from v_dono
                                       or not ((not cf.novato_sozinho and public._agenda_e_novato(x.payee_id, a.dia))
                                               or (not cf.sob_demanda_sozinho and public._agenda_e_sob_demanda(x.payee_id, a.dia)))))
                       or exists (select 1 from jsonb_array_elements(v_ok) y
                                   where y #>> '{para,dia}' = a.dia::text and y #>> '{para,turno}' = a.turno
                                     and not ((not cf.novato_sozinho and public._agenda_e_novato((y #>> '{para,payee_id}')::uuid, a.dia))
                                              or (not cf.sob_demanda_sozinho and public._agenda_e_sob_demanda((y #>> '{para,payee_id}')::uuid, a.dia)))))))
         -- FASE 7b: fim (correção 3)
         -- FASE 7c: (7c P3, R5.3-2) com modo_habilidade ligado, a equipe do meio-dia depois da troca — quem fica de turno na OS ali
         -- (fora as que saem; o dono conta como "você no turno"), os consertos já aceitos ali e o candidato — passa na regra única
         -- (_agenda_atende) com a máscara do meio-dia: o que a OS pede em todos e, se ele é o último que a OS fica tendo (nenhum outro
         -- meio-dia de turno dela — os que ficam, os que ainda vão ser consertados, no lugar de hoje, e os consertos aceitos — vem
         -- depois), o do último, menos quando o fechamento do dono naquele dia cobre (habilidade_fechamento_cobre; a régua de
         -- _agenda_meios_sem_quem_pede). É o (i) e o (ii) do R5.3-2 numa conta só: o novo (papel 2) só entra no meio-dia que fica com
         -- um responsável com instala >= habilidade_nivel_par ou com o dono no turno — nos degraus 2 e 3 a OS não tem meio-dia ali e
         -- ele iria sozinho —, e o ajudante sozinho não entra no meio-dia de risco. Só tira candidato: sem nenhum, a escada não
         -- conserta a OS (tudo ou nada) e o motor replaneja com os filtros da 7c. Fora de ligado, a de antes.
         and (cf.modo_habilidade is distinct from 'ligado'
              or (select public._agenda_atende(
                           v_7c_ext
                           | case when not exists (select 1 from public.agenda_alocacoes x
                                                    where x.service_order_id = p_os and x.estado in ('publicada', 'fixada')
                                                      and x.tipo <> 'reserva' and x.presenca = 'turno'
                                                      and x.id <> (v_v ->> 'alocacao_id')::uuid
                                                      and not exists (select 1 from jsonb_array_elements(v_ok) z
                                                                       where z ->> 'alocacao_id' = x.id::text)
                                                      and (x.dia, x.turno = 'tarde') > (a.dia, a.turno = 'tarde'))
                                       and not exists (select 1 from jsonb_array_elements(v_ok) z
                                                        where ((z #>> '{para,dia}')::date, z #>> '{para,turno}' = 'tarde')
                                                              > (a.dia, a.turno = 'tarde'))
                                       and not (cf.habilidade_fechamento_cobre
                                                and exists (select 1 from public.agenda_alocacoes f
                                                             where f.service_order_id = p_os and f.dia = a.dia and f.presenca = 'fechamento'
                                                               and f.payee_id is not distinct from v_dono and f.estado in ('publicada', 'fixada')))
                                  then v_7c_exu else 0 end,
                           array(select coalesce((v_7c_hab -> e.p::text ->> 0)::int, 0) from unnest(eq.p) with ordinality e(p, o) order by e.o),
                           array(select coalesce((v_7c_hab -> e.p::text ->> 1)::int, 0) from unnest(eq.p) with ordinality e(p, o) order by e.o),
                           array(select coalesce((v_7c_hab -> e.p::text ->> 2)::int, 0) from unnest(eq.p) with ordinality e(p, o) order by e.o),
                           array(select coalesce((v_7c_hab -> e.p::text ->> 3)::int, 0) from unnest(eq.p) with ordinality e(p, o) order by e.o),
                           eq.dt, v_7c_dalt, v_7c_n)
                    from (select coalesce(array_agg(t.p order by t.p) filter (where t.p is distinct from v_dono), '{}'::uuid[]) as p,
                                 coalesce(bool_or(t.p is not distinct from v_dono), false) as dt
                            from (select x.payee_id as p from public.agenda_alocacoes x
                                   where x.service_order_id = p_os and x.estado in ('publicada', 'fixada') and x.tipo <> 'reserva'
                                     and x.presenca = 'turno' and x.dia = a.dia and x.turno = a.turno and not (x.id = any (v_ids))
                                  union all
                                  select (y #>> '{para,payee_id}')::uuid from jsonb_array_elements(v_ok) y
                                   where y #>> '{para,dia}' = a.dia::text and y #>> '{para,turno}' = a.turno
                                  union all
                                  select k.payee_id) t) eq) is null)
         -- FASE 7c: fim
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

  -- FASE 7c: (7c P3, R5.3-2) com modo_habilidade ligado, a conferência do último meio-dia que a OS fica tendo: um degrau 2 ou 3 pode
  -- tirar o último meio-dia do lugar e deixar como último um que ficou (ou um conserto) cuja equipe não tem o que o último pede. A
  -- equipe dele passa na mesma regra (_agenda_atende, com o do último, menos quando o fechamento do dono naquele dia cobre); senão, a
  -- escada não conserta a OS (tudo ou nada: sobra tudo o que saía) e o motor replaneja com os filtros da 7c. Só tira conserto.
  if cf.modo_habilidade = 'ligado' then
    select public._agenda_atende(
             v_7c_ext | case when cf.habilidade_fechamento_cobre
                                  and exists (select 1 from public.agenda_alocacoes f
                                               where f.service_order_id = p_os and f.dia = u.dia and f.presenca = 'fechamento'
                                                 and f.payee_id is not distinct from v_dono and f.estado in ('publicada', 'fixada'))
                             then 0 else v_7c_exu end,
             array(select coalesce((v_7c_hab -> e.p::text ->> 0)::int, 0) from unnest(u.eq) with ordinality e(p, o) order by e.o),
             array(select coalesce((v_7c_hab -> e.p::text ->> 1)::int, 0) from unnest(u.eq) with ordinality e(p, o) order by e.o),
             array(select coalesce((v_7c_hab -> e.p::text ->> 2)::int, 0) from unnest(u.eq) with ordinality e(p, o) order by e.o),
             array(select coalesce((v_7c_hab -> e.p::text ->> 3)::int, 0) from unnest(u.eq) with ordinality e(p, o) order by e.o),
             u.dt, v_7c_dalt, v_7c_n)
      into v_7c_falta
      from (select s.dia, s.turno,
                   coalesce(array_agg(s.p order by s.p) filter (where s.p is distinct from v_dono), '{}'::uuid[]) as eq,
                   coalesce(bool_or(s.p is not distinct from v_dono), false) as dt
              from (select x.dia, x.turno, x.payee_id as p from public.agenda_alocacoes x
                     where x.service_order_id = p_os and x.estado in ('publicada', 'fixada') and x.tipo <> 'reserva'
                       and x.presenca = 'turno' and not (x.id = any (v_ids))
                    union all
                    select (y #>> '{para,dia}')::date, y #>> '{para,turno}', (y #>> '{para,payee_id}')::uuid
                      from jsonb_array_elements(v_ok) y) s
             group by s.dia, s.turno
             order by s.dia desc, s.turno = 'tarde' desc
             limit 1) u;
    if v_7c_falta is not null then
      return v_base || jsonb_build_object('motivo', 'sem_lugar', 'sobrou', to_jsonb(v_ids), 'reparos', v_ok, 'evento_real', v_ev,
                                          'falta_no_fim', v_7c_falta);
    end if;
  end if;
  -- FASE 7c: fim
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
  'Agenda de Produção (Fase 7a, P9; spec §3.3 d11, §5.9, §6.4): a escada de reparo, a conta, sem gravar nada — para a OS com meio-dia de compromisso violado por pessoa (_agenda_violacoes: quem ia não está mais livre), cada meio-dia violado procura, nesta ordem, (1) pessoa: outro diarista livre no mesmo dia e turno, sem outra OS ali; (2) turno: o outro turno do mesmo dia, sem meio-dia da OS, a mesma pessoa se livre; (3) dia: outro dia útil da mesma semana ISO, depois do congelado (no congelado só com o evento real, nunca o que começou), não depois do último dia da OS, sem meio-dia dela, sem mais dias parados do que ela já tinha (ou interrupcoes_max). Cada candidato só vale com as 14 regras do motor (_agenda_validar_itens) sobre o conjunto. Degraus 2 e 3 só no meio-dia em que a OS tem só essa pessoa, nunca antes da abertura nem depois do fechamento do dono. Tudo ou nada por OS (sobrou = vai inteira ao motor). Violação de outro motivo, da reserva, do dono ou do fixado pelo dono: não é da escada. {os, numero, reparavel, motivo?, degrau, itens (o formato de agenda_propor), texto ("Lenine qua 04/11 de manhã: troquei João por Roberto (João não vem)."; "Lenine qua 04/11: passei a manhã para a tarde, com Roberto."; "Lenine: passei qua 04/11 de manhã para sex 06/11 de manhã (mesma semana; o fim não muda)."), reparos, sobrou, fim_antes, fim_depois, evento_real}. STABLE, invoker, sem grant. CORREÇÃO 3 DA 7b (o R5.9 da spec da 7c; o bloco (i) do R5.3-2 na versão 7b): com modo_dupla fora de desligado, quem nunca fica sozinho (o novato da 7b, com novato_sozinho falso; quem vem sob demanda, com sob_demanda_sozinho falso — _agenda_e_novato e _agenda_e_sob_demanda no dia do meio-dia) só entra no degrau 1 e só no meio-dia que fica com outra pessoa de turno da OS que pode ficar sozinha (fora as que saem; também um conserto já aceito ali) ou com o dono no turno; nunca nos degraus 2 e 3. Só tira candidato: sem nenhum, a OS não é consertada (sobrou) e vai ao motor. Com modo_dupla desligado, ou com um candidato que pode ficar sozinho, a de antes, byte a byte. FASE 7c (P3, R5.3-2): com modo_habilidade ligado, a régua da 7c no lugar da da 7b — o candidato só vale se a equipe do meio-dia depois da troca (quem fica de turno na OS ali, os consertos já aceitos ali e ele) passa em _agenda_atende com a máscara do meio-dia (o que a OS pede em todos e, no último meio-dia que a OS fica tendo, o do último, menos quando o fechamento do dono naquele dia cobre): o novo (papel 2 de agenda_habilidades em p_hoje, também o dia fixo sem diária) só no meio-dia que fica com um responsável com instala >= habilidade_nivel_par ou com o dono no turno, nunca nos degraus 2 e 3; o ajudante sozinho nunca no meio-dia de risco; e, no fim, o último meio-dia que a OS fica tendo passa na mesma regra (senão sem_lugar, com falta_no_fim). O que a OS pede só com a porta de os_exigencias aberta (para a técnica logada, nada em especial: só o novo nunca sozinho). Só tira candidato. Fora de ligado, a de antes (a da correção 3 da 7b), byte a byte.';

-- ── 3. Portas ────────────────────────────────────────────────────────────────────────────────────────────────────
-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar): a violação só do
-- service_role (o motor e a vigia a chamam como definer); a escada para ninguém (só as funções definer da agenda a chamam).
revoke all on function public._agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date) from public, anon, authenticated;
grant execute on function public._agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date) to service_role;
revoke all on function public._agenda_gestor_reparo(uuid, date, timestamptz) from public, anon, authenticated, service_role;
