-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P13 (7a-1): o bem livre — a pergunta ao dono.
-- Quando o gestor marca sozinho o 1º dia de um serviço, ele conta que o barco ou o motorhome está livre e no lugar de sempre, e
-- diz isso ao dono uma vez, sem prazo e sem opções: "Lenine (OS-00074): marquei a partir de ter 03/11 contando que o motorhome
-- está livre e no lugar de sempre. Se ele estiver em uso ou em outro lugar, me diga até quando (ex.: 'motorhome de Lenine fora
-- até 20/11')." Nada vai ao cliente: a pergunta "onde fica e quando precisa" ao cliente é o M11 onde_fica do 7d, que fecha esta
-- pergunta quando o cliente responde.
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R3 "P13 NÃO manda mensagem ao cliente", §0 item 6 (h), §5.13, §6.3 bem_livre,
-- §8.4 agenda_fase7a_bem.sql, §9 P13); nomes: fase7-registro.md §1 (_agenda_gestor_bem; o tipo bem_livre, criado no 7a P1) e §3
-- (o pacote 13, "renomeada (era _bem_ocupado); só _agenda_gestor_bem").
-- Depende da 20261031100000 (7a P1: o tipo bem_livre na lista fechada e o modo dele em _agenda_modo_da_pergunta, recriado depois
-- no 7a P11), da 20261031100300 (7a P4: o gravador das perguntas do gestor) e da 20261031100600 (7a P7: a rodada, que acha o
-- passo bem por to_regprocedure, em todo tique, logo depois do encaixe); antes delas, das Fases 1 a 6 (os_planejamento.
-- bem_indisponivel, da Fase 1; os_planejamento.acesso_ok_em e cliente_acesso_validade_dias, da Fase 5).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (1 função nova; nenhuma recriada; nenhuma tabela, coluna, lista, dado, cron ou tela muda)
-- NÃO APLICADA. Nenhuma função é recriada aqui: a rodada do gestor (agenda_gestor_rodar, 7a P7, recriada no 7a P10) já tem o passo
-- bem na lista de todo tique e o pula enquanto ele não existe ("ainda não existe"); o despacho das decisões (agenda_decidir, 7a P4)
-- já responde "Essa pergunta não tem opções" a bem_livre; o modo da pergunta (_agenda_modo_da_pergunta) já é o do gestor que marca;
-- e a limpeza da vigia já fecha a pergunta cuja OS saiu da carteira. Por isso este arquivo não foi montado por um montador (não há
-- corpo copiado) e o O3 de supabase/tests/agenda_fase7a_bem.sql confere que ele só cria o passo.
--
-- POR QUE: D7-1 e D7-3 — o gestor marca firme sozinho e o dono corrige depois. A marcação supõe que o bem está livre e onde sempre
-- esteve; o dono tem de saber dessa suposição na hora, porque um motorhome em viagem ou um barco na água num dia marcado é o dia
-- perdido da equipe (spec §0 item 6 (h)). Ao cliente não vai nada aqui (spec §R3): a pergunta a ele é a do 7d (M11).
--
-- O QUE MUDA:
--   1. _agenda_gestor_bem (novo passo de todo tique da rodada do gestor): para cada OS da carteira que tem dia de compromisso de
--      hoje em diante, cujo 1º dia o motor escolheu (alocação de origem motor: não foi o dono nem o cliente quem pediu o dia),
--      que ainda não começou (sem check-in, sem "em andamento", sem meio-dia cumprido ou
--      parcial) e sem o bem dito (os_planejamento.bem_indisponivel de hoje em diante) nem o acesso confirmado
--      (os_planejamento.acesso_ok_em dentro de cliente_acesso_validade_dias): a pergunta bem_livre ao dono (chave
--      bem_livre:<os>, uma vez por OS, sem opções, sem prazo, sem opção padrão, não crítica; o texto da §6.3). Só com o gestor que
--      marca ligado de verdade (_agenda_modo_da_pergunta('bem_livre') = ligado; em teste e com *gestor, só propor*, {pulado}).
--      Em qualquer modo, a pergunta aberta que não vale mais é resolvida sozinha: a OS saiu da carteira, o serviço já começou, o
--      bem foi dito ("já foi dito até quando o motorhome fica fora"), o acesso foi confirmado ou a OS não tem mais dia marcado.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_bem.sql; registradas em notas-fase77a.md, P13):
--   · "A OS que ganhou o 1º compromisso desde a última rodada (ações criar/promover_reserva do gestor)" virou: a OS com dia de
--     compromisso cujo 1º dia o motor escolheu e que ainda não começou, uma vez por OS (a fechada não volta na mesma chave) — é a
--     mesma coisa sem depender da rodada anterior (o molde do passo sinal, 7a P12). O 1º dia pedido pelo dono ou pelo cliente não
--     pergunta (quem escolheu o dia já sabe do bem); o serviço que já começou também não (o bem está lá).
--   · "Sem bem_indisponivel dito" = sem intervalo de hoje em diante (um "fora" que já passou não diz nada do bem agora); "sem
--     acesso_ok_em" = sem o acesso dito dentro de cliente_acesso_validade_dias (a régua da Fase 5 para "o acesso é conhecido").
--   · A pergunta aberta que não vale mais é resolvida pelo próprio passo (os 5 motivos acima), em qualquer modo: sem isso ela ficaria
--     aberta até vencer (7 dias) depois do bem dito, do acesso confirmado ou do serviço começar. A resposta do cliente é do 7d.
--   · O nome sem artigo (spec §6): "motorhome de Lenine", não "do Lenine" (o exemplo da §6.3). O bem pela régua do planejar
--     (agenda_rascunho_planejar): motorhome (ou trailer) = "o motorhome", o resto = "o barco". O dia do exemplo é o último dia
--     marcado + 10 dias corridos (fora do que marquei, para não ser lido como uma data do plano; no Lenine, 20/11, o da §6.3).
--
-- ORDEM DE LIGAR (spec §10): nada liga aqui. O passo segue o modo do gestor que marca: pergunta só com ele ligado (passo 6 de
-- fila-do-dono/fase7a-oks.md). Desfazer só a pergunta do bem: drop do passo (abaixo); a rodada volta a pulá-lo.
--
-- PROVA: supabase/tests/agenda_fase7a_bem.sql (O0–O3), na bancada (node scripts/bancada-agenda/rodar.mjs).
--
-- APLICAR (depois do OK nomeado, com as 20261031100000–100900 já aplicadas):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100950_agenda_fase7a_bem.sql
--
-- DESFAZER:
--   drop function if exists public._agenda_gestor_bem(date, timestamptz);
--   (sem o passo, a rodada do gestor o pula: "ainda não existe"; as perguntas bem_livre abertas vencem sozinhas em 7 dias, pela
--   limpeza da vigia.)
--
-- IDEMPOTENTE: create or replace function, comment e revoke.

-- ── 1. A função nova: o passo bem da rodada do gestor (agenda_gestor_rodar, P7, o acha por to_regprocedure) ──────────────────

-- _agenda_gestor_bem(p_hoje, p_agora): o passo bem, em TODO tique (logo depois do encaixe, na lista da rodada).
create or replace function public._agenda_gestor_bem(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_validade smallint;
  v_cart     uuid[];
  v_modo     text;
  v_res      int := 0;
  v_novas    int := 0;
  v_lista    jsonb := '[]'::jsonb;
  v_mot      text;
  v_txt      text;
  v_id       uuid;
  r          record;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_bem: sem o dia ou a hora' using errcode = '22004';
  end if;
  select c.cliente_acesso_validade_dias into v_validade from public.agenda_config c where c.id;
  select coalesce(array_agg(k.service_order_id), '{}'::uuid[]) into v_cart from public.os_carteira(p_hoje) k;

  -- 1. a pergunta aberta que não vale mais some sozinha (em qualquer modo): a OS saiu da carteira, o serviço começou, o bem foi
  --    dito (de hoje em diante), o acesso foi confirmado (dentro da validade) ou a OS não tem mais dia marcado
  for r in
    select q.id, q.service_order_id as os,
           (so.check_in_at is not null or so.status = 'in_progress'
            or exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = q.service_order_id and a.estado in ('publicada', 'fixada')
                          and a.tipo <> 'reserva' and a.resultado in ('cumprido', 'parcial'))) as comecou,
           coalesce(pl.bem_indisponivel && datemultirange(daterange(p_hoje, null, '[)')), false) as bem_dito,
           coalesce(pl.acesso_ok_em is not null
                    and (pl.acesso_ok_em at time zone 'America/Sao_Paulo')::date > p_hoje - v_validade, false) as acesso_ok,
           case when public._agenda_normal(coalesce(vs.asset_type, vs.name)) ~ 'motorhome|motor home|trailer'
                then 'motorhome' else 'barco' end as bem
      from public.agenda_perguntas q
      left join public.service_orders so on so.id = q.service_order_id
      left join public.vessels vs on vs.id = so.vessel_id
      left join public.os_planejamento pl on pl.service_order_id = q.service_order_id
     where q.tipo = 'bem_livre' and q.estado = 'aberta'
     order by q.criada_em, q.id
  loop
    v_mot := case when r.os is null or not (r.os = any (v_cart)) then 'a OS saiu da carteira'
                  when r.comecou then 'o serviço já começou'
                  when r.bem_dito then format('já foi dito até quando o %s fica fora', r.bem)
                  when r.acesso_ok then 'o acesso foi confirmado'
                  when not public._agenda_os_tem_dia(r.os, p_hoje) then 'a OS não está mais marcada na agenda' end;
    if v_mot is not null then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = v_mot where id = r.id;
      v_res := v_res + 1;
    end if;
  end loop;

  -- 2. a pergunta nova só com o gestor marcando de verdade (em teste nada é marcado: não há o que supor do bem)
  v_modo := coalesce(public._agenda_modo_da_pergunta('bem_livre', null), 'desligado');
  if v_modo <> 'ligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'o gestor não marca sozinho', 'modo', v_modo, 'resolvidas', v_res);
  end if;
  for r in
    select k.service_order_id as os, k.numero, coalesce(k.cliente_curto, k.numero) as cliente, x.de, x.ate,
           case when public._agenda_normal(coalesce(vs.asset_type, vs.name)) ~ 'motorhome|motor home|trailer'
                then 'motorhome' else 'barco' end as bem
      from public.os_carteira(p_hoje) k
      join public.service_orders so on so.id = k.service_order_id
      join public.vessels vs on vs.id = so.vessel_id
      left join public.os_planejamento pl on pl.service_order_id = k.service_order_id
      cross join lateral (
        select min(a.dia) as de, max(a.dia) as ate from public.agenda_alocacoes a
         where a.service_order_id = k.service_order_id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
           and a.dia >= p_hoje and a.resultado is distinct from 'nao_cumprido') x
     where x.de is not null
       -- o 1º dia foi o motor quem escolheu (não o pedido do dono nem o do cliente)
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = k.service_order_id and a.estado in ('publicada', 'fixada')
                          and a.tipo <> 'reserva' and a.dia = x.de and a.origem <> 'motor')
       -- ainda não começou
       and so.check_in_at is null and so.status is distinct from 'in_progress'
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = k.service_order_id and a.estado in ('publicada', 'fixada')
                          and a.tipo <> 'reserva' and a.resultado in ('cumprido', 'parcial'))
       -- nem o bem dito de hoje em diante nem o acesso confirmado
       and not coalesce(pl.bem_indisponivel && datemultirange(daterange(p_hoje, null, '[)')), false)
       and not coalesce(pl.acesso_ok_em is not null
                        and (pl.acesso_ok_em at time zone 'America/Sao_Paulo')::date > p_hoje - v_validade, false)
     order by k.numero collate "C", k.service_order_id
  loop
    v_txt := format('%s (%s): marquei a partir de %s contando que o %s está livre e no lugar de sempre. Se ele estiver em uso '
                    'ou em outro lugar, me diga até quando (ex.: ''%s de %s fora até %s'').',
                    r.cliente, r.numero, public._dia_curto(r.de), r.bem, r.bem, r.cliente, to_char(r.ate + 10, 'DD/MM'));
    v_id := public._agenda_gestor_perguntar('bem_livre', 'bem_livre:' || r.os, r.os, v_txt, '[]'::jsonb, null::smallint,
                                            null::timestamptz, null::smallint, v_modo, p_agora);
    continue when v_id is null;
    if exists (select 1 from public.agenda_perguntas q where q.id = v_id and q.criada_em = p_agora) then
      v_novas := v_novas + 1;
    end if;
    v_lista := v_lista || jsonb_build_object('os', r.os, 'numero', r.numero, 'pergunta_id', v_id, 'texto', v_txt);
  end loop;
  return jsonb_build_object('modo', v_modo, 'perguntas', jsonb_array_length(v_lista), 'novas', v_novas, 'resolvidas', v_res,
                            'os', v_lista);
end;
$function$;

comment on function public._agenda_gestor_bem(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P13; spec §5.13 e §6.3): o passo bem da rodada do gestor, em todo tique. Quando o gestor marca sozinho, ele supõe que o bem está livre e no lugar de sempre e diz isso ao dono — para cada OS da carteira com dia de compromisso de hoje em diante cujo 1º dia o motor escolheu (alocação de origem motor), que ainda não começou (sem check-in, sem in_progress, sem meio-dia cumprido ou parcial) e sem o bem dito de hoje em diante (os_planejamento.bem_indisponivel) nem o acesso confirmado dentro de cliente_acesso_validade_dias (os_planejamento.acesso_ok_em), a pergunta bem_livre (chave bem_livre:<os>, uma vez por OS, sem opções e sem prazo): "Lenine (OS-00074): marquei a partir de ter 03/11 contando que o motorhome está livre e no lugar de sempre. Se ele estiver em uso ou em outro lugar, me diga até quando (ex.: ''motorhome de Lenine fora até 20/11'')." (o bem pela régua do planejar: motorhome ou trailer = motorhome, o resto = barco; o dia do exemplo = o último dia marcado + 10). Só com o modo do gestor que marca ligado de verdade; senão {pulado}. A aberta some sozinha, em qualquer modo: a OS saiu da carteira, o serviço já começou, o bem foi dito, o acesso foi confirmado ou a OS não tem mais dia. Nenhuma mensagem ao cliente (a pergunta "onde fica e quando precisa" ao cliente é o M11 onde_fica do 7d, que fecha esta quando o cliente responde). {modo, perguntas, novas, resolvidas, os [{os, numero, pergunta_id, texto}]}. Invoker, sem grant (só a rodada do gestor o chama).';

-- ── 2. Portas ──────────────────────────────────────────────────────────────────────────────────────────────────
-- O passo escreve perguntas (pelo gravador definer do P4) e as resolve: sem grant a ninguém, nem service_role (só a rodada do
-- gestor, definer, o chama). Nunca anon (spec §3.1 item 10).
revoke all on function public._agenda_gestor_bem(date, timestamptz) from public, anon, authenticated, service_role;
