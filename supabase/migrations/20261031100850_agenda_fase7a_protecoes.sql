-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P11 (7a-1): as proteções do cliente e da equipe.
-- O dia que o gestor marcou pela estimativa do orçamento não chega a quem é de fora sem o dono ter podido ver. Ao CLIENTE: a
-- confirmação do dia, a nova data e o "o material chegou" de uma OS marcada pela estimativa pedem o sim do dono (*manda cliente*)
-- nos 3 primeiros dias desse tipo aprovados por estimativa, mesmo com o tipo já liberado; a véspera não muda (o dia de início já é
-- real) e nenhum texto novo vai ao cliente (a semana prevista é do 7f). À EQUIPE: nas primeiras 3 semanas depois do ligar do
-- gestor, a ficha de um dia pela estimativa só sai se o dono viu a pergunta no fechamento ("Hoje às 19:30 a ficha de amanhã vai
-- para Roberto: Lenine, ter 03/11 o dia todo — dia 1 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu
-- não mando e você fala com ele.") e não a segurou; senão ela fica registrada como recusada (veto), nada vai à fila e o dono fica
-- sabendo pelo que mudou.
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R3, §3.2 "Cliente" e "Equipe", §5.4 _agenda_gestor_decidir, §5.11, §6.3
-- ficha_estimativa, §6.5, §6.6, §8.3 F, §8.4, §11 aceite 7); nomes: fase7-registro.md §1 (_agenda_os_por_estimativa,
-- _agenda_os_compra_pendente, _agenda_cliente_estimativa_liberada, _agenda_gestor_fichas, _agenda_ficha_liberada) e §2 (a cadeia de
-- _agenda_cliente_registrar e _agenda_rotina_ficha); respostas do dono: fase7-padroes.md (AG7-15 "sem resposta fica como
-- proposto"; AG7-16 "semana prevista até ficar seguro").
-- Depende da 20261031100000 (7a P1: ficha_veto_dias, marcar_sozinho_desde, a recusa veto, o tipo ficha_estimativa, a coluna
-- agenda_alocacoes.duracao_fonte e o gatilho dela), da 20261031100300 (7a P4: o gravador das perguntas, o prazo e o despacho), da
-- 20261031100600 (7a P7: a rodada, que acha o passo fichas, o fechamento e os zeros cliente_estimativa_sem_aprovacao e
-- ficha_estimativa_sem_veto da saúde) e da 20261031100750 (7a P9: o despacho mais novo); antes delas, das Fases 1 a 6 e do lote de
-- 30/10.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (5 funções novas e 7 recriadas; nenhuma tabela, coluna, lista, dado, cron ou tela muda)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7a/p11/montar-migration.mjs: as 7 recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote e nas 20261031* dos
-- pacotes anteriores): _agenda_cliente_registrar de 20261029100900, _agenda_rotina_ficha, _agenda_rotina_como_foi e
-- _agenda_rotina_confirmar de 20261026100300, _agenda_gestor_decidir de 20261031100750 (7a P9), _agenda_linhas_do_fechamento de
-- 20261031100600 (7a P7) e _agenda_modo_da_pergunta de 20261031100000 (7a P1). As mudanças estão só nos blocos
-- "-- FASE 7: (7a P11 … -- FASE 7: fim"; fora deles nenhuma linha muda (o P4 de supabase/tests/agenda_fase7a_protecoes.sql
-- confere). Sem dia marcado pela estimativa (nenhuma alocação de duracao_fonte orcamento) e sem o ligar do gestor
-- (marcar_sozinho_desde nulo), as sete dão o de antes, byte a byte; a única troca fora disso é o modo de quem faz a pergunta
-- ficha_estimativa (o das mensagens à equipe), um tipo que só o passo fichas desta migration grava.
--
-- POR QUE: com o gestor ligado (D7-1), o dia marcado pela estimativa ainda não passou pelo dono. AG7-16: o cliente só ouve o dia
-- com o sim do dono nos primeiros dias; AG7-15: a equipe só recebe a ficha de um dia por estimativa, nas primeiras semanas, se o
-- dono pôde ver e segurar.
--
-- O QUE MUDA:
--   1. _agenda_os_por_estimativa (nova): a OS tem compromisso de hoje em diante marcado pela estimativa e os dias não são do dono.
--   2. _agenda_os_compra_pendente (nova): algum item crítico da prontidão falta comprar ou foi comprado sem previsão.
--   3. _agenda_cliente_estimativa_liberada (nova): o tipo já somou cliente_aprovacao_dias dias aprovados por estimativa.
--   4. _agenda_cliente_registrar (recriada): confirmar, nova_data e material_chegou de OS por estimativa levam
--      base.dados.por_estimativa e pedem o sim do dono (a pergunta cliente_aprovar) enquanto o tipo não somou os 3 dias.
--   5. _agenda_gestor_fichas (novo passo diário fichas da rodada do gestor): a pergunta ficha_estimativa por pessoa com dia pela
--      estimativa no próximo dia útil, na janela de veto, com o prazo na hora da ficha.
--   6. _agenda_ficha_liberada (nova): a ficha da pessoa no dia pode sair.
--   7. _agenda_rotina_ficha (recriada): a ficha não liberada fica recusada (veto) e, se o dono não soube, a ação equipe da vigia
--      conta ("Não mandei a ficha de ter 03/11 a Roberto (Lenine): o dia é pela minha estimativa e você não viu a pergunta antes
--      das 19:30. Fale com Roberto."); a pergunta do dia fecha.
--   8. _agenda_gestor_decidir (recriada): a ficha_estimativa — 1 mande, 2 segure (só com o dono), sem resposta até o prazo vale a 1.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_protecoes.sql e no cenário F do agenda_fase7a_replay.sql;
-- registradas em notas-fase77a.md, P11):
--   · _agenda_linhas_do_fechamento recriada (fora da spec): a pergunta da ficha de hoje vai numa linha própria do fechamento das
--     17:30, perda 75. Na vaga da pergunta de fato (perda 30) ela quase nunca entraria, e a ficha ficaria segurada todo dia.
--   · _agenda_rotina_como_foi recriada (fora da spec): nos dias em que a confirmação da manhã saiu, a ficha de amanhã vai junto do
--     "como foi hoje?" das 17:00, antes do fechamento e da hora da ficha. A de um dia por estimativa na janela só vai junto com o
--     "mande" do dono; senão a rotina das 19:30 decide.
--   · _agenda_rotina_confirmar recriada (fora da spec): a confirmação da manhã de um dia cuja ficha não pôde sair também não sai.
--     Ela diria o dia de que o dono ficou de falar com a pessoa ("Segure a ficha: eu não mando").
--   · _agenda_modo_da_pergunta recriada (fora do registro): a ficha_estimativa é das mensagens à equipe (modo_equipe), não do
--     gestor que marca. Com *gestor, só propor*, a pergunta nasceria em teste e a ficha ficaria segurada sem o dono poder soltá-la.
--   · A janela de veto é contada pelo dia da ficha (o dia de que ela fala), como o zero ficha_estimativa_sem_veto da saúde (P7);
--     a spec dizia p_hoje. O "dia pela estimativa" da ficha é a alocação da pessoa no dia com duracao_fonte orcamento, também a
--     régua da saúde.
--
-- ORDEM DE LIGAR (spec §10): nada liga aqui. A proteção da equipe só existe depois do "OK ligar o gestor"
-- (marcar_sozinho_desde), por ficha_veto_dias (21); a do cliente, com dia marcado pela estimativa e o modo_cliente da Fase 5.
-- Desfazer só a da equipe: ficha_veto_dias = 0 (a janela fecha; as fichas saem como antes).
--
-- PROVA: supabase/tests/agenda_fase7a_protecoes.sql (P0–P5) e o cenário F de supabase/tests/agenda_fase7a_replay.sql, na bancada
-- (node scripts/bancada-agenda/rodar.mjs).
--
-- APLICAR (depois do OK nomeado, com as 20261031100000–100800 já aplicadas):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100850_agenda_fase7a_protecoes.sql
--
-- DESFAZER: reaplicar as definições de antes (as migrations de origem citadas acima, na ordem) e
--   drop function if exists public._agenda_gestor_fichas(date, timestamptz), public._agenda_ficha_liberada(uuid, date, timestamptz),
--     public._agenda_cliente_estimativa_liberada(text), public._agenda_os_compra_pendente(uuid, date),
--     public._agenda_os_por_estimativa(uuid, date);
--   (sem o passo fichas, a rodada do gestor o pula: "ainda não existe"; as perguntas ficha_estimativa abertas vencem sozinhas).
--
-- IDEMPOTENTE: create or replace function, comment, revoke e grant.

-- ── 1. As funções novas ──────────────────────────────────────────────────────────────────────────────────────

-- A OS está marcada pela estimativa do gestor (spec §5.11)? Algum compromisso vigente dela (publicado ou fixado, sem reserva) de
-- p_dia em diante nasceu com a duração da estimativa (duracao_fonte orcamento, o gatilho _agenda_alocacao_fonte do P1) e os dias
-- dela não são do dono (os_planejamento.estimativa_fonte fora de dono/aceita: o dono que disse os dias tirou a estimativa). A
-- mensagem ao cliente (_agenda_cliente_registrar) e o 7f (_agenda_cliente_camada) leem daqui. STABLE, invoker.
create or replace function public._agenda_os_por_estimativa(p_os uuid, p_dia date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select p_os is not null and p_dia is not null
     and exists (select 1 from public.agenda_alocacoes a
                  where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    and a.dia >= p_dia and a.duracao_fonte = 'orcamento')
     and not exists (select 1 from public.os_planejamento pl
                      where pl.service_order_id = p_os and pl.estimativa_fonte in ('dono', 'aceita'));
$function$;

comment on function public._agenda_os_por_estimativa(uuid, date) is
  'Agenda de Produção (Fase 7a, P11; AG7-16): a OS está marcada pela estimativa do gestor — algum compromisso vigente (publicado ou fixado, sem reserva) de p_dia em diante com duracao_fonte orcamento, e os dias dela não são do dono (os_planejamento.estimativa_fonte fora de dono/aceita). Lida pela mensagem ao cliente (_agenda_cliente_registrar: base.dados.por_estimativa) e pelo 7f (a semana prevista). STABLE, invoker; authenticated e service_role.';

-- A OS tem compra pendente (spec §5.11)? Algum item crítico da prontidão que não está na mão nem dispensado e ainda falta comprar
-- (situacao falta) ou foi comprado sem previsão (sem_data: o nível E, ou o D sem data). É o que a Fase 5 já barra no M1 (o
-- material tem de estar completo) e o que o 7f usa para a semana prevista. STABLE, invoker.
create or replace function public._agenda_os_compra_pendente(p_os uuid, p_hoje date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select p_os is not null and p_hoje is not null
     and exists (select 1 from jsonb_array_elements(coalesce(public.os_prontidao(p_os, p_hoje) #> '{material,itens}', '[]'::jsonb)) e
                  where coalesce((e ->> 'critico')::boolean, true)
                    and coalesce(e ->> 'situacao', 'falta') not in ('na_mao', 'dispensado')
                    and (coalesce(e ->> 'situacao', 'falta') = 'falta' or coalesce((e ->> 'sem_data')::boolean, false)));
$function$;

comment on function public._agenda_os_compra_pendente(uuid, date) is
  'Agenda de Produção (Fase 7a, P11; AG7-16): a OS tem compra pendente — algum item crítico da prontidão (os_prontidao.material.itens) que não está na mão nem dispensado e falta comprar (situacao falta) ou foi comprado sem previsão (sem_data). A OS por estimativa com compra pendente não recebe dia (o M1 da Fase 5 já exige o material completo; a semana prevista é do 7f). STABLE, invoker; authenticated e service_role.';

-- A aprovação "por estimativa" de um tipo de mensagem ao cliente já somou cliente_aprovacao_dias dias DISTINTOS (Brasília,
-- aprovada_em) com mensagem desse tipo de base.dados.por_estimativa aprovada pelo dono (da rodada e em ligado, a régua de
-- _agenda_cliente_tipo_liberado)? Enquanto não, a mensagem por estimativa pede o sim do dono, mesmo com o tipo já liberado.
create or replace function public._agenda_cliente_estimativa_liberada(p_tipo text)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select (public._agenda_cfg()).cliente_aprovacao_dias = 0
      or (select count(distinct (m.aprovada_em at time zone 'America/Sao_Paulo')::date)
            from public.agenda_cliente_mensagens m
           where m.tipo = p_tipo and m.aprovacao = 'aprovada' and m.origem = 'rodada' and m.modo = 'ligado'
             and m.base -> 'dados' ->> 'por_estimativa' = 'true')
         >= (public._agenda_cfg()).cliente_aprovacao_dias;
$function$;

comment on function public._agenda_cliente_estimativa_liberada(text) is
  'Agenda de Produção (Fase 7a, P11; AG7-16, d11): a mensagem ao cliente por estimativa de um tipo já sai sem o dono? Somou agenda_config.cliente_aprovacao_dias dias distintos (Brasília, aprovada_em) com mensagem desse tipo de base.dados.por_estimativa aprovada pelo dono (aprovacao aprovada, origem rodada, modo ligado — a régua de _agenda_cliente_tipo_liberado). 0 = sempre liberada. STABLE, invoker; authenticated e service_role.';

-- A ficha (ou a confirmação da manhã) de uma pessoa num dia pode sair (spec §3.2 "Equipe" e §5.11; AG7-15)? Sim fora da janela de
-- veto (sem o ligar do gestor, marcar_sozinho_desde nulo, ou o dia fora das ficha_veto_dias a partir dele), para o dono e para o
-- dia sem compromisso da pessoa marcado pela estimativa (alocação dela no dia com duracao_fonte orcamento: a régua do zero
-- ficha_estimativa_sem_veto da saúde). Senão só com a pergunta ficha_estimativa daquele dia (de verdade) mostrada ao dono
-- (mostrada_vezes > 0, até p_agora) e não segurada (opção 2). STABLE, invoker.
create or replace function public._agenda_ficha_liberada(p_payee uuid, p_dia date, p_agora timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_payee is null or p_dia is null or p_agora is null then true
    when cf.marcar_sozinho_desde is null then true
    when p_dia < (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date
      or p_dia >= (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date + cf.ficha_veto_dias then true
    when p_payee is not distinct from public._agenda_dono(null) then true
    when not exists (select 1 from public.agenda_alocacoes a
                      where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                        and a.duracao_fonte = 'orcamento') then true
    else exists (select 1 from public.agenda_perguntas q
                  where q.chave = format('ficha_estimativa:%s:%s', p_payee, p_dia) and q.modo = 'ligado'
                    and q.mostrada_vezes > 0 and q.mostrada_em <= p_agora and q.opcao_escolhida is distinct from 2)
  end
    from public.agenda_config cf
   where cf.id;
$function$;

comment on function public._agenda_ficha_liberada(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P11; AG7-15): a ficha (e a confirmação da manhã) da pessoa no dia pode sair? true fora da janela de veto (marcar_sozinho_desde nulo, ou p_dia fora de [o dia do ligar, + ficha_veto_dias)), para o dono e para o dia sem alocação vigente da pessoa com duracao_fonte orcamento; senão só com a pergunta ficha_estimativa:<pessoa>:<dia> de verdade (modo ligado) mostrada ao dono até p_agora e não segurada (opcao_escolhida distinta de 2). Lida por _agenda_rotina_ficha, _agenda_rotina_como_foi e _agenda_rotina_confirmar (recriadas pelo P11). STABLE, invoker; authenticated e service_role.';

-- O passo diário "fichas" da rodada do gestor (spec §5.11 e §6.3; AG7-15): nas primeiras ficha_veto_dias a partir do ligar do
-- gestor, para cada pessoa da rotina (agenda_equipe_contato) com compromisso marcado pela estimativa no próximo dia útil, a pergunta
-- ficha_estimativa (chave ficha_estimativa:<pessoa>:<dia>; prazo = hoje às equipe_hora_ficha; sem resposta, 1 = mande):
-- "Hoje às 19:30 a ficha de amanhã vai para Roberto: Lenine, ter 03/11 o dia todo — dia 1 de 6, pela minha estimativa. 1) Mande
-- (recomendo); 2) Segure a ficha: eu não mando e você fala com ele." O modo é o de quem faz a pergunta (_agenda_modo_da_pergunta:
-- o das mensagens à equipe, modo_equipe): desligado = nada. O fechamento das 17:30 a mostra numa linha própria; a ficha das 19:30
-- só sai com ela mostrada e não segurada. Invoker, sem grant: só a rodada do gestor o chama (os diários, depois da revisão).
create or replace function public._agenda_gestor_fichas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_modo  text;
  v_desde date;
  v_d     date;
  v_ate   timestamptz;
  v_hora  text;
  v_quando text;
  v_dono  uuid := public._agenda_dono(null);
  p       record;
  v_os    uuid;
  v_partes text[];
  v_txt   text;
  v_id    uuid;
  v_novas int := 0;
  v_lista jsonb := '[]'::jsonb;
  v_ops   jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_fichas: sem o dia ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_modo := coalesce(public._agenda_modo_da_pergunta('ficha_estimativa', null), 'desligado');
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'as mensagens à equipe estão desligadas');
  end if;
  if cf.marcar_sozinho_desde is null then
    return jsonb_build_object('pulado', true, 'motivo', 'o gestor ainda não marca sozinho: sem janela da ficha');
  end if;
  if not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('pulado', true, 'motivo', 'não é dia útil');
  end if;
  v_desde := (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date;
  v_d := public.agenda_somar_du(p_hoje, 1);
  if v_d < v_desde or v_d >= v_desde + cf.ficha_veto_dias then
    return jsonb_build_object('pulado', true, 'motivo', 'fora da janela da ficha', 'dia', v_d);
  end if;
  v_ate := (p_hoje + cf.equipe_hora_ficha) at time zone 'America/Sao_Paulo';
  if p_agora >= v_ate then
    return jsonb_build_object('pulado', true, 'motivo', 'já passou a hora da ficha', 'dia', v_d);
  end if;
  v_hora := to_char(cf.equipe_hora_ficha, 'HH24:MI');
  v_quando := case when v_d = p_hoje + 1 then 'amanhã'
                   else (array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])[extract(isodow from v_d)::int] end;
  v_ops := jsonb_build_array(
    jsonb_build_object('n', 1, 'texto', 'Mande', 'efeito', jsonb_build_object('mandar', true)),
    jsonb_build_object('n', 2, 'texto', 'Segure a ficha: eu não mando e você fala com ele', 'efeito', jsonb_build_object('segurar', true)));

  for p in
    select c.payee_id, public._agenda_nome_curto(py.name) as nome
      from public._agenda_contatos_com_plano(v_d) c(payee_id)
      join public.payees py on py.id = c.payee_id
     where c.payee_id is distinct from v_dono
       and exists (select 1 from public.agenda_alocacoes a
                    where a.payee_id = c.payee_id and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      and a.duracao_fonte = 'orcamento')
       -- a ficha desse dia já foi decidida (registrada, ou de carona no "como foi hoje?"): não há o que perguntar
       and not exists (select 1 from public.agenda_equipe_mensagens m
                        where m.payee_id = c.payee_id and m.modo = 'ligado'
                          and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)))
     order by 2, 1
  loop
    -- o que a ficha diz desse dia pela estimativa: cada OS dele no dia, o turno e que dia é do plano dela
    select array_agg(format('%s, %s %s — dia %s de %s', o.cliente, public._dia_curto(v_d),
                            case when o.m and o.t then 'o dia todo' when o.m then 'de manhã' else 'à tarde' end, o.k, o.n)
                     order by o.ini, o.os),
           (array_agg(o.os order by o.ini, o.os))[1]
      into v_partes, v_os
      from (select a.service_order_id as os, min(lower(a.periodo)) as ini,
                   bool_or(a.turno = 'manha') as m, bool_or(a.turno = 'tarde') as t,
                   coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cliente,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno' and b.dia <= v_d) as k,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno') as n
              from public.agenda_alocacoes a
              join public.service_orders so on so.id = a.service_order_id
              left join public.clients cl on cl.id = so.client_id
             where a.payee_id = p.payee_id and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
               and a.duracao_fonte = 'orcamento'
             group by a.service_order_id, cl.name, so.service_order_number) o;
    v_txt := format('Hoje às %s a ficha de %s vai para %s: %s, pela minha estimativa.', v_hora, v_quando, p.nome,
                    array_to_string(v_partes, '; '))
             || ' 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.';
    v_id := public._agenda_gestor_perguntar('ficha_estimativa', format('ficha_estimativa:%s:%s', p.payee_id, v_d), v_os, v_txt,
                                            v_ops, 1::smallint, v_ate, 1::smallint, v_modo, p_agora);
    if v_id is not null and exists (select 1 from public.agenda_perguntas q where q.id = v_id and q.criada_em = p_agora) then
      v_novas := v_novas + 1;
    end if;
    v_lista := v_lista || jsonb_build_object('pessoa', p.payee_id, 'nome', p.nome, 'pergunta_id', v_id, 'texto', v_txt);
  end loop;
  return jsonb_build_object('dia', v_d, 'prazo', v_ate, 'modo', v_modo, 'perguntas', jsonb_array_length(v_lista),
                            'novas', v_novas, 'pessoas', v_lista);
end;
$function$;

comment on function public._agenda_gestor_fichas(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P11; AG7-15, spec §5.11 e §6.3): o passo diário fichas da rodada do gestor — com o ligar do gestor (marcar_sozinho_desde) e o próximo dia útil dentro das ficha_veto_dias a partir dele, para cada pessoa da rotina (_agenda_contatos_com_plano, sem o dono) com alocação vigente nesse dia de duracao_fonte orcamento e sem a ficha do dia já decidida, a pergunta ficha_estimativa (chave ficha_estimativa:<pessoa>:<dia>; veto_ate = hoje às equipe_hora_ficha; opções 1 Mande / 2 Segure; recomendação e padrão 1): "Hoje às 19:30 a ficha de amanhã vai para Roberto: Lenine, ter 03/11 o dia todo — dia 1 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele." (o dia que não é amanhã pelo nome: "a ficha de terça"). O modo é o de _agenda_modo_da_pergunta(''ficha_estimativa'') — o das mensagens à equipe; desligado, fora da janela, depois da hora da ficha ou fora de dia útil = {pulado}. {dia, prazo, modo, perguntas, novas, pessoas [{pessoa, nome, pergunta_id, texto}]}. Invoker, sem grant.';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7: (7a P11") ────────────────
-- Fora dos blocos nenhuma linha muda (o P4 de supabase/tests/agenda_fase7a_protecoes.sql confere). Quem recriar de novo qualquer
-- uma delas copia DESTA migration (fase7-registro.md §2: _agenda_cliente_registrar no 7e P5, _agenda_rotina_ficha no 7f P5;
-- _agenda_gestor_decidir no 7a P12; _agenda_rotina_como_foi, _agenda_rotina_confirmar, _agenda_linhas_do_fechamento e
-- _agenda_modo_da_pergunta, quem vier — o 7b P1, o 7c P1/P8, o 7d P1 e o 7g P1 recriam _agenda_modo_da_pergunta para os tipos
-- novos deles: copiam daqui).

-- _agenda_cliente_registrar (de 20261029100900_agenda_fase6_correcao_calculo.sql)
create or replace function public._agenda_cliente_registrar(p_tipo text, p_variante text, p_os uuid, p_dia_alvo date,
                                                            p_dados jsonb, p_alvo timestamptz, p_valida_ate timestamptz,
                                                            p_origem text, p_critica text default null,
                                                            p_agora timestamptz default now(), p_autor uuid default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_tique constant interval := interval '15 minutes';   -- o tique do motor: o que sai até o próximo entra na fila agora
  v_hoje  date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_dados jsonb := coalesce(p_dados, '{}'::jsonb) - 'primeira' - 'envio' - 'chave' - 'prometido_tipo';
  x       jsonb;
  v_cli   uuid;
  v_modo  text;
  v_chave text;
  v_id    uuid := gen_random_uuid();
  v_ja    uuid;
  v_enviar timestamptz;
  v_valida timestamptz;
  v_prim  boolean;
  v_var   text := nullif(btrim(coalesce(p_variante, '')), '');
  v_txt   text;
  v_proib text;
  v_prom  text;
  v_aprov text;
  v_estado text := 'registrada';
  v_recusa text;
  v_perg  uuid;
  v_base  jsonb;
  v_r     jsonb;
  v_acao  uuid;
  v_aut   uuid;
  -- CORREÇÃO FASE 5: (item 12) a hora do meio-dia da saudação ("Bom dia" antes, "Boa tarde" depois: é o português, não
  -- um parâmetro da agenda nem o fim do turno da manhã)
  c_meio_dia_h constant int := 12;
  -- CORREÇÃO FASE 5: fim
  -- CORREÇÃO FASE 6: (C1) item 4: a folga do aviso em uso (dias úteis)
  v_folga int;
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P11) a mensagem com dia de uma OS marcada pela estimativa do gestor
  v_f11_est boolean := false;
  -- FASE 7: fim
begin
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('criada', false, 'modo', 'desligado');
  end if;
  if p_origem is null or p_origem not in ('rodada', 'dono', 'botao') then
    raise exception 'A mensagem ao cliente vem da rodada, do dono ou do botão (veio %).', coalesce(p_origem, 'nada') using errcode = '22023';
  end if;
  if p_critica is not null and p_critica not in ('segundo_atraso', 'atraso_longo', 'passou', 'teto') then
    raise exception 'Motivo de aviso crítico desconhecido: %.', p_critica using errcode = '22023';
  end if;
  if p_alvo is null then
    raise exception 'A mensagem ao cliente veio sem a hora.' using errcode = '22023';
  end if;
  select so.client_id into v_cli from public.service_orders so where so.id = p_os;
  if v_cli is null then
    raise exception 'A mensagem ao cliente veio sem a OS (ou a OS sem cliente).' using errcode = '22023';
  end if;
  x := public._agenda_cliente_contexto(p_os, v_hoje);

  -- o modo da linha: ligado só com modo_cliente ligado E o tipo na lista das ondas; senão em teste (a chave com :sombra)
  v_modo := case when cf.modo_cliente = 'ligado' and p_tipo = any (cf.cliente_tipos_ligados) then 'ligado' else 'sombra' end;
  v_chave := format('agenda-cliente:%s:%s:%s', p_tipo, p_os,
                    coalesce(nullif(btrim(p_dados ->> 'chave'), ''), p_dia_alvo::text,
                             to_char(p_alvo at time zone 'America/Sao_Paulo', 'YYYY-MM-DD')))
             || case when v_modo = 'sombra' then ':sombra' else '' end;
  select m.id into v_ja from public.agenda_cliente_mensagens m where m.dedupe_key = v_chave;
  if v_ja is not null then
    return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe', 'id', v_ja);
  end if;

  -- a hora (a janela, o feriado, o intervalo) e o texto contado do dia em que ele SAI (o "Amanhã"), com a assinatura só na
  -- 1ª mensagem; o registro guarda os dois (a revalidação recalcula com eles)
  v_enviar := public._agenda_cliente_quando(hashtext(v_chave), p_alvo, p_agora);
  -- CORREÇÃO FASE 5: (item 12) a saudação dos que abrem com ela (a véspera, o acesso e a mudança no dia por chuva) segue a
  -- hora em que a mensagem SAI (Brasília): "Bom dia" antes do meio-dia, "Boa tarde" depois. Fica em p_dados (e em
  -- base.dados): a revalidação recalcula igual, e a hora que muda depois (a conversa viva) não a deixa desatualizada.
  if p_tipo in ('vespera', 'acesso', 'mudanca_no_dia') then
    v_dados := v_dados || jsonb_build_object('saudacao',
                 case when extract(hour from (v_enviar at time zone 'America/Sao_Paulo')) < c_meio_dia_h then 'Bom dia'
                      else 'Boa tarde' end);
  end if;
  -- CORREÇÃO FASE 5: fim
  v_prim := coalesce((p_dados ->> 'primeira')::boolean, (x ->> 'primeira')::boolean, false);
  if p_tipo = 'confirmar' and v_var is null then
    v_var := case when v_prim then 'primeira' else 'seguinte' end;
  end if;
  v_txt := public._agenda_cliente_texto(p_tipo, v_var, p_os,
             v_dados || jsonb_build_object('primeira', v_prim, 'envio', (v_enviar at time zone 'America/Sao_Paulo')::date), v_hoje);
  v_proib := public._agenda_cliente_texto_proibido(v_txt);
  if v_proib is not null then
    raise exception 'A mensagem ao cliente não pode levar % (o texto: "%").', v_proib, left(v_txt, 120) using errcode = '22023';
  end if;
  -- o que a mensagem DIZ de data (vira o prometido quando sai): firme nos modelos com dia; faixa no atraso da peça e da
  -- execução (condicional, se o passo disser); nada no andamento, no pronto e no pós-serviço
  v_prom := coalesce(nullif(btrim(p_dados ->> 'prometido_tipo'), ''),
                     case when p_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
                               or (p_tipo = 'pode_atrasar' and v_var = 'remarcado') then 'firme'
                          when p_tipo = 'pode_atrasar' then 'faixa' end);
  if v_prom is not null and v_prom not in ('condicional', 'faixa', 'firme') then
    raise exception 'O que a mensagem diz de data é condicional, faixa ou firme (veio %).', v_prom using errcode = '22023';
  end if;
  -- CORREÇÃO FASE 5: (item 8) o aviso "ainda faltam peças sem data" não diz data: não vira prometido (ao sair, o gatilho do
  -- envio tira o que o cliente tinha ouvido)
  if p_tipo = 'pode_atrasar' and v_var = 'peca_sem_data' then
    v_prom := null;
  end if;
  -- CORREÇÃO FASE 5: fim
  -- CORREÇÃO FASE 6: (C1) item 4: o aviso de atraso da peça e da execução com a folga do aprendizado em uso (o mesmo
  -- _agenda_aprendido('aviso_folga', 'todas') que _agenda_cliente_risco somou ao fim da faixa) guarda em base.dados o fim da
  -- faixa SEM a folga (faixa_ate_plano): é contra ele que a medição mede o estouro (senão a folga aprenderia contra ela
  -- mesma e iria de 2 a 0 e de volta). O texto e a chave não mudam.
  if p_tipo = 'pode_atrasar' and v_var in ('peca', 'execucao') and (v_dados ->> 'faixa_ate') is not null then
    v_folga := coalesce(round(public._agenda_aprendido('aviso_folga', 'todas'))::int, 0);
    if v_folga > 0 then
      v_dados := v_dados || jsonb_build_object('faixa_ate_plano',
                                               public.agenda_somar_du((v_dados ->> 'faixa_ate')::date, -v_folga));
    end if;
  end if;
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P11, spec §3.2 "Cliente" e §5.11; AG7-16) a mensagem com dia (confirmar, nova_data, material_chegou) de uma OS
  -- marcada pela estimativa do gestor (_agenda_os_por_estimativa: compromisso de duracao_fonte orcamento de agora em diante, sem
  -- os dias do dono) leva base.dados.por_estimativa — o que a aprovação abaixo e o zero cliente_estimativa_sem_aprovacao da saúde
  -- leem. A véspera e os outros tipos não mudam. Nenhum texto novo ao cliente.
  if p_tipo in ('confirmar', 'nova_data', 'material_chegou')
     and public._agenda_os_por_estimativa(p_os, coalesce(p_dia_alvo, (p_dados ->> 'dia')::date, v_hoje)) then
    v_dados := v_dados || jsonb_build_object('por_estimativa', true);
    v_f11_est := true;
  end if;
  -- FASE 7: fim
  v_valida := coalesce(p_valida_ate, public._agenda_cliente_fim_da_janela((v_enviar at time zone 'America/Sao_Paulo')::date, 0));
  v_base := jsonb_build_object(
    'status', x ->> 'status',
    'dia_alvo', coalesce((p_dados ->> 'dia')::date, (x ->> 'dia')::date, p_dia_alvo),
    'fim', coalesce((p_dados ->> 'fim')::date, (x ->> 'fim')::date),
    'nivel', x ->> 'nivel_material',
    'prometido_ate', x #>> '{prometido,ate}',
    'primeira', v_prim,
    'envio', (v_enviar at time zone 'America/Sao_Paulo')::date,
    'referencia', case when x -> 'plano' is null or jsonb_typeof(x -> 'plano') = 'null' then 'agendada' else 'plano' end,
    'dados', v_dados);

  -- a aprovação (em ligado): a crítica pergunta (cliente_aviso); a do dono e a do tipo ainda não liberado pedem *manda
  -- cliente* (cliente_aprovar); a do botão já foi aprovada pelo clique; o resto sai sozinho. Em teste, sempre livre.
  if v_enviar > v_valida then
    v_aprov := 'livre';
    v_estado := 'recusada';
    v_recusa := 'vencida';
  elsif v_modo = 'sombra' then
    v_aprov := 'livre';
  elsif p_critica is not null then
    v_aprov := 'critica';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aviso',
                format('cliente_aviso:%s:%s', p_os, coalesce(p_dia_alvo, (v_enviar at time zone 'America/Sao_Paulo')::date)),
                p_os, p_dia_alvo, (v_enviar at time zone 'America/Sao_Paulo')::date,
                public._agenda_cliente_texto_do_aviso(p_critica, p_tipo, p_os, p_dados, v_hoje), 'ligado', p_agora, v_valida);
  elsif p_origem = 'botao' then
    v_aprov := 'aprovada';
    v_aut := (select u.id from public.app_users u where u.id = p_autor);
  elsif p_origem = 'dono' or not public._agenda_cliente_tipo_liberado(p_tipo) then
    v_aprov := 'pedida';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:' || v_id, p_os, p_dia_alvo,
                (v_enviar at time zone 'America/Sao_Paulo')::date,
                case when p_origem = 'dono'
                     then format('Pronto para o %s, sai %s: "%s". Para mandar: *manda cliente %s*.', x ->> 'nome',
                                 public._agenda_cliente_quando_texto(v_enviar, p_agora), v_txt, x ->> 'nome')
                     else format('Mensagem para o %s (%s), sai %s: "%s". *manda cliente %s* ou *segura cliente %s*.', x ->> 'nome',
                                 public._agenda_cliente_tipo_texto(p_tipo), public._agenda_cliente_quando_texto(v_enviar, p_agora),
                                 v_txt, x ->> 'nome', x ->> 'nome') end,
                'ligado', p_agora, v_valida);
  -- FASE 7: (7a P11) por estimativa: o sim do dono (*manda cliente*) até somar cliente_aprovacao_dias dias distintos aprovados por
  -- estimativa desse tipo (_agenda_cliente_estimativa_liberada), mesmo com o tipo já liberado (d11). A crítica, o botão e a do
  -- dono seguem acima, como antes.
  elsif v_f11_est and not public._agenda_cliente_estimativa_liberada(p_tipo) then
    v_aprov := 'pedida';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:' || v_id, p_os, p_dia_alvo,
                (v_enviar at time zone 'America/Sao_Paulo')::date,
                format('Mensagem para %s (%s; o dia é pela minha estimativa), sai %s: "%s". *manda cliente %s* ou *segura cliente %s*.',
                       x ->> 'nome', public._agenda_cliente_tipo_texto(p_tipo), public._agenda_cliente_quando_texto(v_enviar, p_agora),
                       v_txt, x ->> 'nome', x ->> 'nome'),
                'ligado', p_agora, v_valida);
  -- FASE 7: fim
  else
    v_aprov := 'livre';
  end if;

  insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de,
                                               faixa_ate, prometido_tipo, modo, texto, base, enviar_em, valida_ate, aprovacao,
                                               pergunta_id, aprovada_em, aprovada_por, estado, recusa_motivo, dedupe_key,
                                               criada_em)
  values (v_id, v_cli, p_os, p_tipo, v_var, p_origem, p_dia_alvo, (p_dados ->> 'faixa_de')::date,
          (p_dados ->> 'faixa_ate')::date, v_prom, v_modo, v_txt, v_base, v_enviar, v_valida, v_aprov, v_perg,
          case when v_aprov = 'aprovada' then p_agora end, v_aut, v_estado, v_recusa, v_chave, p_agora);

  -- CORREÇÃO FASE 5: (item 15) a linha da sombra sem artigo antes do nome ("Em teste: eu teria mandado para Lucenira …"; a
  -- ação não muda depois de gravada, então ela já nasce assim). O bloco de 20261028100300 logo abaixo não roda mais para a
  -- sombra (v_modo fica 'sombra_feita' só entre os dois blocos).
  if v_modo = 'sombra' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), v_hoje, false, 'vigia', 'cliente', p_os, array[p_os], '{}'::jsonb,
            jsonb_build_object('mensagem_id', v_id, 'tipo', p_tipo, 'enviar_em', v_enviar),
            left(format('Em teste: eu teria mandado para %s %s (sairia %s).', x ->> 'nome',
                        public._agenda_cliente_o_que(p_tipo, coalesce((v_base ->> 'dia_alvo')::date, p_dia_alvo)),
                        public._agenda_cliente_quando_texto(v_enviar, p_agora)), 400))
    returning id into v_acao;
    update public.agenda_cliente_mensagens set acao_id = v_acao where id = v_id;
    v_modo := 'sombra_feita';
  end if;
  -- CORREÇÃO FASE 5: fim
  -- em teste: o que a agenda teria mandado (a linha do que mudou sozinho, sem executar)
  if v_modo = 'sombra' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), v_hoje, false, 'vigia', 'cliente', p_os, array[p_os], '{}'::jsonb,
            jsonb_build_object('mensagem_id', v_id, 'tipo', p_tipo, 'enviar_em', v_enviar),
            left(format('Em teste: eu teria mandado ao %s %s (sairia %s).', x ->> 'nome',
                        public._agenda_cliente_o_que(p_tipo, coalesce((v_base ->> 'dia_alvo')::date, p_dia_alvo)),
                        public._agenda_cliente_quando_texto(v_enviar, p_agora)), 400))
    returning id into v_acao;
    update public.agenda_cliente_mensagens set acao_id = v_acao where id = v_id;
  end if;

  -- CORREÇÃO FASE 5: (item 15) o modo volta a ser o da linha
  if v_modo = 'sombra_feita' then
    v_modo := 'sombra';
  end if;
  -- CORREÇÃO FASE 5: fim
  -- o que sai até o próximo tique entra na fila agora; o de depois fica registrado e o passo "fila" o enfileira na hora
  if v_modo = 'ligado' and v_estado = 'registrada' and v_aprov in ('livre', 'aprovada') and v_enviar <= p_agora + c_tique then
    v_r := public._agenda_cliente_enfileirar(v_id, p_agora);
  end if;
  return jsonb_build_object('criada', true, 'id', v_id, 'modo', v_modo, 'estado', v_estado, 'motivo', v_recusa,
                            'aprovacao', v_aprov, 'pergunta_id', v_perg, 'enviar_em', v_enviar, 'valida_ate', v_valida,
                            'texto', v_txt)
         || coalesce(v_r, '{}'::jsonb);
end;
$function$;

comment on function public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid) is
  'Agenda de Produção (Fase 5, P2): grava a mensagem-modelo ao cliente e decide o envio — desligado = nada; o texto é o do banco (_agenda_cliente_texto, contado do dia do envio, com a assinatura só na 1ª mensagem; o proibido = 22023); o modo da linha: ligado só com modo_cliente ligado E o tipo em cliente_tipos_ligados, senão sombra (chave com :sombra, a ação "Em teste: eu teria mandado…"); a chave agenda-cliente:<tipo>:<os>:<p_dados.chave | dia_alvo | o dia do alvo> (uma só: a 2ª devolve ja_existe); enviar_em pelo _agenda_cliente_quando; valida_ate = p_valida_ate, senão o fim da janela do dia do envio (passou dela = recusada/vencida); a aprovação em ligado: p_critica (segundo_atraso, atraso_longo, passou, teto) = critica + pergunta cliente_aviso; origem dono ou tipo ainda não liberado = pedida + pergunta cliente_aprovar; botão = aprovada (aprovada_por = p_autor); senão livre. base guarda {status, dia_alvo, fim, nivel, prometido_ate, primeira, envio, referencia, dados} para a revalidação. A livre/aprovada que sai até o próximo tique vai a _agenda_cliente_enfileirar. p_dados: os do modelo (dia, fim, janela, n, faixa_de/ate, peca_de/ate, dito_de/ate, dia_dito, quando, n_feitos), primeira, prometido_tipo, chave (o sufixo da chave no lugar do dia: o lembrete e o andamento semanal), atraso_dias (o aviso crítico). Sem grant. CORREÇÃO FASE 5 (C2): (item 12) a véspera, o acesso e a mudança no dia ganham p_dados.saudacao pela hora do envio (Brasília: "Bom dia" antes das 12:00, "Boa tarde" depois), guardada em base.dados; (item 8) o M6 peca_sem_data não tem prometido_tipo; (item 15) a ação da sombra sem artigo antes do nome. CORREÇÃO FASE 6 (C1, item 4): o aviso de atraso (peca/execucao) com a folga do aprendizado em uso guarda em base.dados.faixa_ate_plano o fim da faixa sem a folga (a medição mede o estouro contra ele). FASE 7 (7a P11, spec §3.2 "Cliente" e §5.11; AG7-16): confirmar, nova_data e material_chegou de uma OS marcada pela estimativa do gestor (_agenda_os_por_estimativa no dia da mensagem) levam base.dados.por_estimativa = true e, fora da crítica, do botão e da do dono, pedem o sim do dono (aprovacao pedida, a pergunta cliente_aprovar "Mensagem para Lenine (confirmação do dia; o dia é pela minha estimativa), sai …") enquanto o tipo não somou cliente_aprovacao_dias dias distintos aprovados por estimativa (_agenda_cliente_estimativa_liberada), mesmo com o tipo já liberado. O texto ao cliente não muda; a véspera e os outros tipos, também não. Sem OS por estimativa, a de antes, byte a byte.';

-- _agenda_rotina_ficha (de 20261026100300_agenda_fase3_equipe_diarias.sql)
create or replace function public._agenda_rotina_ficha(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_modo  text := public._agenda_modo_da_equipe();
  v_d     date;
  v_p     uuid;
  v_f     jsonb;
  v_r     jsonb;
  v_cont  jsonb := '{}'::jsonb;
  -- FASE 7: (7a P11) a ficha de um dia pela estimativa, na janela de veto
  v_f11_q   public.agenda_perguntas%rowtype;
  v_f11_m   uuid;
  v_f11_a   uuid;
  v_f11_os  uuid[];
  v_f11_cli text;
  v_f11_nom text;
  -- FASE 7: fim
begin
  if v_local::time < cf.equipe_hora_ficha or not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('fichas', 0);
  end if;
  v_d := public.agenda_somar_du(p_hoje, 1);
  for v_p in select x from public._agenda_contatos_com_plano(v_d) x loop
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo
                             and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)));
    v_f := public.agenda_equipe_ficha(v_p, v_d, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    -- FASE 7: (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15) nas primeiras ficha_veto_dias a partir do ligar do gestor, a ficha de
    -- um dia marcado pela estimativa (a alocação da pessoa no dia com duracao_fonte orcamento) só sai com a pergunta
    -- ficha_estimativa daquele dia mostrada ao dono e não segurada (_agenda_ficha_liberada). Senão ela fica registrada como
    -- recusada (veto): nada vai à fila nem conta no teto da pessoa. Se o dono não soube (não viu a pergunta a tempo, ou ela nem
    -- nasceu), o que mudou conta para ele (a ação equipe da vigia: o fechamento e o *o que mudou* do dia seguinte). A pergunta do
    -- dia fecha aqui: a hora da ficha chegou. Só com a mensagem de verdade (em teste nada sai de todo jeito).
    if v_modo = 'ligado' then
      v_f11_q := null;
      select q.* into v_f11_q from public.agenda_perguntas q
       where q.chave = format('ficha_estimativa:%s:%s', v_p, v_d) and q.modo = 'ligado'
       order by q.criada_em desc, q.id desc limit 1;
      if not public._agenda_ficha_liberada(v_p, v_d, p_agora) then
        insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key,
                                                    criada_em)
        values (v_p, v_d, 'ficha', 'ligado', left(v_f ->> 'texto_ficha', 600), p_agora, 'recusada', 'veto',
                format('agenda-equipe:ficha:%s:%s', v_p, v_d), p_agora)
        returning id into v_f11_m;
        if v_f11_q.id is null or v_f11_q.opcao_escolhida is distinct from 2 then
          v_f11_os := array(select a.service_order_id from public.agenda_alocacoes a
                             where a.payee_id = v_p and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.duracao_fonte = 'orcamento'
                             group by a.service_order_id order by min(lower(a.periodo)), a.service_order_id);
          v_f11_cli := public._agenda_lista(array(
                         select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                           from unnest(v_f11_os) with ordinality u(os, o)
                           join public.service_orders so on so.id = u.os left join public.clients cl on cl.id = so.client_id
                          order by u.o), null);
          v_f11_nom := (select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_p);
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
          values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', v_f11_os[1], v_f11_os, v_p,
                  jsonb_build_object('motivo', 'ficha_segurada', 'dia', v_d, 'mensagem', v_f11_m, 'pergunta', v_f11_q.id,
                                     'por', case when v_f11_q.id is null then 'sem_pergunta' else 'nao_vista' end),
                  left(format('Não mandei a ficha de %s a %s (%s): o dia é pela minha estimativa e %s. Fale com %s.',
                              public._dia_curto(v_d), v_f11_nom, v_f11_cli,
                              case when v_f11_q.id is null then 'não consegui te perguntar antes'
                                   else 'você não viu a pergunta antes das ' || to_char(cf.equipe_hora_ficha, 'HH24:MI') end,
                              v_f11_nom), 400))
          returning id into v_f11_a;
          update public.agenda_equipe_mensagens set acao_id = v_f11_a where id = v_f11_m;
        end if;
        update public.agenda_perguntas
           set estado = 'resolvida', resolvida_motivo = 'na hora da ficha você não tinha visto a pergunta: a ficha não saiu'
         where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
        v_cont := v_cont || jsonb_build_object('recusada', coalesce((v_cont ->> 'recusada')::int, 0) + 1);
        continue;
      end if;
      update public.agenda_perguntas
         set estado = 'resolvida', resolvida_motivo = 'na hora da ficha você não a segurou: ela foi como eu disse'
       where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
    end if;
    -- FASE 7: fim
    v_r := public._agenda_equipe_registrar(v_p, v_d, 'ficha', v_f ->> 'texto_ficha', p_agora);
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('dia', v_d, 'por_estado', v_cont);
end;
$function$;

-- (a 20261026100300 não comenta a função)
comment on function public._agenda_rotina_ficha(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a ficha da véspera (equipe_hora_ficha num dia útil) para o próximo dia útil — não vai a quem já recebeu a ficha desse dia nem a quem recebeu o "como foi hoje?" levando a ficha; o texto de agenda_equipe_ficha, pelo _agenda_equipe_registrar. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15): com a mensagem de verdade, a ficha que _agenda_ficha_liberada não solta (na janela de veto do ligar, um dia da pessoa marcado pela estimativa sem a pergunta ficha_estimativa mostrada, ou segurada com a 2) fica registrada como recusada (veto) — nada vai à fila nem conta no teto — e, se o dono não soube, a ação equipe da vigia conta no que mudou ("Não mandei a ficha de ter 03/11 a Roberto (Lenine): o dia é pela minha estimativa e você não viu a pergunta antes das 19:30. Fale com Roberto."); a pergunta do dia fecha (resolvida). Fora disso, a de antes, byte a byte.';

-- _agenda_rotina_como_foi (de 20261026100300_agenda_fase3_equipe_diarias.sql)
create or replace function public._agenda_rotina_como_foi(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_modo  text := public._agenda_modo_da_equipe();
  v_d     date := public.agenda_somar_du(p_hoje, 1);
  v_p     uuid;
  v_f     jsonb;
  v_fd    jsonb;
  v_leva  boolean;
  v_r     jsonb;
  v_cont  jsonb := '{}'::jsonb;
begin
  if v_local::time < cf.equipe_hora_como_foi then
    return jsonb_build_object('como_foi', 0);
  end if;
  for v_p in select x from public._agenda_contatos_com_plano(p_hoje) x loop
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'como_foi' and m.dia = p_hoje);
    v_f := public.agenda_equipe_ficha(v_p, p_hoje, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    v_leva := exists (select 1 from public.agenda_equipe_mensagens m
                       where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'confirmar' and m.dia = p_hoje
                         and m.estado <> 'recusada')
              and not exists (select 1 from public.agenda_equipe_mensagens m
                               where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'ficha' and m.dia = v_d);
    v_fd := case when v_leva then public.agenda_equipe_ficha(v_p, v_d, p_hoje) end;
    v_leva := v_leva and coalesce((v_fd ->> 'tem_plano')::boolean, false);
    -- FASE 7: (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15) a ficha de amanhã que iria junto do "como foi hoje?" obedece a mesma
    -- proteção da ficha das 19:30 (_agenda_ficha_liberada) e mais: o "como foi" sai antes da hora da ficha, quando o dono ainda
    -- pode segurá-la; então a ficha de um dia pela estimativa na janela de veto só vai junto com o "mande" dele (opção 1). Senão o
    -- "como foi" vai sem ela, e a rotina da hora da ficha decide.
    if v_leva and v_modo = 'ligado'
       and (not public._agenda_ficha_liberada(v_p, v_d, p_agora)
            or exists (select 1 from public.agenda_perguntas q
                        where q.chave = format('ficha_estimativa:%s:%s', v_p, v_d) and q.modo = 'ligado'
                          and q.opcao_escolhida is distinct from 1)) then
      v_leva := false;
    end if;
    -- FASE 7: fim
    v_r := public._agenda_equipe_registrar(v_p, p_hoje, 'como_foi',
             (v_f ->> 'texto_como_foi') || case when v_leva then ' ' || (v_fd ->> 'texto_curto') else '' end,
             p_agora, case when v_leva then v_d end);
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('por_estado', v_cont);
end;
$function$;

-- (a 20261026100300 não comenta a função)
comment on function public._agenda_rotina_como_foi(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): o "como foi hoje?" (equipe_hora_como_foi) a quem teve plano hoje; no dia em que a confirmação da manhã saiu, ele leva a ficha de amanhã (e a hora da ficha não manda nada). FASE 7 (7a P11; AG7-15): a ficha de amanhã de um dia pela estimativa na janela de veto só vai junto com o "mande" do dono (a opção 1 da pergunta ficha_estimativa) — o "como foi" sai antes do fechamento e da hora da ficha; sem isso (ou com _agenda_ficha_liberada falso), ele vai sem a ficha e a rotina da hora da ficha decide. Fora disso, a de antes, byte a byte.';

-- _agenda_rotina_confirmar (de 20261026100300_agenda_fase3_equipe_diarias.sql)
create or replace function public._agenda_rotina_confirmar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_modo  text := public._agenda_modo_da_equipe();
  v_p     uuid;
  v_f     jsonb;
  v_r     jsonb;
  v_cont  jsonb := '{}'::jsonb;
begin
  if v_local::time < cf.equipe_hora_confirmar or v_local::time >= cf.equipe_silencio_ate then
    return jsonb_build_object('confirmar', 0);
  end if;
  for v_p in select x from public._agenda_contatos_com_plano(p_hoje) x loop
    continue when exists (select 1 from public.agenda_disponibilidade d
                           where d.payee_id = v_p and d.substituida_em is null and d.situacao = 'confirmada'
                             and d.turno is null and d.periodo @> p_hoje);
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo and m.tipo = 'confirmar' and m.dia = p_hoje);
    v_f := public.agenda_equipe_ficha(v_p, p_hoje, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    -- FASE 7: (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15) a confirmação da manhã de um dia pela estimativa cuja ficha não pôde
    -- sair (o dono a segurou, ou não viu a pergunta a tempo: _agenda_ficha_liberada falso) também não sai — ela diria o dia de que
    -- o dono ficou de falar com a pessoa. Fica registrada como recusada (veto); nada vai à fila (e o silêncio das 9h só conta a
    -- confirmação que saiu). Só com a mensagem de verdade.
    if v_modo = 'ligado' and not public._agenda_ficha_liberada(v_p, p_hoje, p_agora) then
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key,
                                                  criada_em)
      values (v_p, p_hoje, 'confirmar', 'ligado', left(v_f ->> 'texto_confirmar', 600), p_agora, 'recusada', 'veto',
              format('agenda-equipe:confirmar:%s:%s', v_p, p_hoje), p_agora);
      v_cont := v_cont || jsonb_build_object('recusada', coalesce((v_cont ->> 'recusada')::int, 0) + 1);
      continue;
    end if;
    -- FASE 7: fim
    v_r := public._agenda_equipe_registrar(v_p, p_hoje, 'confirmar', v_f ->> 'texto_confirmar', p_agora);
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('por_estado', v_cont);
end;
$function$;

-- (a 20261026100300 não comenta a função)
comment on function public._agenda_rotina_confirmar(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a confirmação da manhã (equipe_hora_confirmar, antes de equipe_silencio_ate) só a quem não confirmou o dia. FASE 7 (7a P11; AG7-15): com a mensagem de verdade, a do dia que _agenda_ficha_liberada não solta (a ficha não pôde sair: segurada pelo dono ou a pergunta não vista) fica registrada como recusada (veto) e nada vai à fila. Fora disso, a de antes, byte a byte.';

-- _agenda_gestor_decidir (de 20261031100750_agenda_fase7a_revisao.sql)
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
  -- FASE 7: (7a P11) a ficha da equipe de um dia pela estimativa
  v_f11_p   uuid;
  v_f11_d   date;
  v_f11_n   text;
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
  -- FASE 7: (7a P11, spec §5.11 e §6.3; AG7-15) a ficha da equipe de um dia pela estimativa, na janela de veto do ligar:
  --   1) Mande — fica respondida e a ficha sai na hora dela (_agenda_ficha_liberada);
  --   2) Segure — fica respondida; a ficha e a confirmação da manhã desse dia não saem (a rotina as registra como recusadas: veto)
  --      e o dono fala com a pessoa. A 2 nunca vale sem resposta.
  --   Sem resposta até o prazo (a hora da ficha), com a pergunta mostrada antes (o passo vetos), vale a 1: fica resolvida.
  if v_q.tipo = 'ficha_estimativa' then
    select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
    if v_opc is null then
      return jsonb_build_object('ok', false, 'gestor', true,
        'texto', 'Essa opção não existe. As opções são: '
                 || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                       from jsonb_array_elements(v_q.opcoes) o) || '.');
    end if;
    v_ef := coalesce(v_opc -> 'efeito', '{}'::jsonb);
    if not (v_ef ? 'mandar' or v_ef ? 'segurar') then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
    end if;
    v_f11_p := nullif(split_part(v_q.chave, ':', 2), '')::uuid;
    v_f11_d := nullif(split_part(v_q.chave, ':', 3), '')::date;
    v_f11_n := coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_f11_p), 'a pessoa');
    if v_prazo then
      if not (v_ef ? 'mandar') then
        return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não vale sem resposta: nada mudou.');
      end if;
      v_ate := public._dia_curto((v_q.veto_ate at time zone 'America/Sao_Paulo')::date) || ' às '
               || to_char(v_q.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI');
      update public.agenda_perguntas
         set estado = 'resolvida',
             resolvida_motivo = left(format('sem resposta até %s: a ficha vai como eu disse', replace(v_ate, ' às ', ' ')), 200)
       where id = v_q.id;
      return jsonb_build_object('ok', true, 'gestor', true, 'via', p_via, 'pessoa', v_f11_p, 'dia', v_f11_d,
        'texto', format('Sem resposta até %s: a ficha de %s vai para %s como eu disse.', v_ate, public._dia_curto(v_f11_d), v_f11_n));
    end if;
    -- quem responde viu a pergunta: sem a conta de mostrada (respondeu pela conversa ou pela tela), ela passa a contar agora — a
    -- ficha (_agenda_ficha_liberada) e o zero ficha_estimativa_sem_veto da saúde leem a mostrada
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via,
           mostrada_vezes = greatest(mostrada_vezes, 1), mostrada_em = coalesce(mostrada_em, p_agora),
           mostrada_via = coalesce(mostrada_via, 'conversa')
     where id = v_q.id;
    return jsonb_build_object('ok', true, 'gestor', true, 'pessoa', v_f11_p, 'dia', v_f11_d,
      'texto', case when v_ef ? 'mandar'
                    then format('Combinado: mando a ficha de %s para %s.', public._dia_curto(v_f11_d), v_f11_n)
                    else format('Combinado: não mando a ficha de %s para %s, nem a confirmação da manhã. Fale com %s.',
                                public._dia_curto(v_f11_d), v_f11_n, v_f11_n) end);
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
  'Agenda de Produção (Fase 7a, P4): o despacho das perguntas do gestor (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal), chamado por agenda_decidir (o dono) e por _agenda_gestor_vetos (p_via prazo). Só situacao e estimativa decidem aqui (os outros tipos: "não tem opções" ou "ainda não sei decidir", até os pacotes P8, P9, P11 e P12 recriarem ESTA função). Opção com efeito dias: se a pergunta que o gestor faria agora para a OS ainda é esta, grava os dias (_agenda_gestor_gravar_dias; a pergunta respondida pelo dono, ou resolvida "sem resposta até sex 30/10 18:00: ficou como eu disse"); senão resolve a pergunta e nada muda. dizer: fica aberta com a escolha (o prazo não vale mais), "Me diga os dias (ex.: ''Nelson 3 dias'')."; terminou: "Use *concluiu Nelson*."; nao_fazer: "não marco". Só com a pergunta e o modo de quem a fez ligados. Trava agenda_plano. {ok, gestor true, texto, acao_id?, aberta?, sem_condicao?}. Security definer, sem grant a ninguém. FASE 7 (7a P8, spec §5.8): a onda — com a agenda na mesma versão do plano da pergunta, a conta é refeita pelo motor com os parâmetros da proposta dela (agenda_propor persistido, criada_por dono) e aplicada com a pergunta (ações críticas): 1 tudo ("Feito: …"); 2 só as OS de evento real, o de hoje e amanhã (sem nenhuma: "Não havia nada de hoje e amanhã para mudar: não mudei nada."); 3 nada (a proposta descartada; "Combinado: não mudei nada. …"). Com a agenda mudada desde a pergunta, a pergunta resolve e nada muda ("A agenda mudou desde a pergunta: …"). Falhou = nada fica, a pergunta continua aberta. Sem prazo (via prazo: "Essa pergunta não tem prazo"). O P9 e o P12 recriam esta função copiando DESTA migration. FASE 7 (7a P9, spec §5.9 e §6.3): reavaliar (sem prazo) — 1 "Use *concluiu Rodrigo*."; 2 "Me diga o que mais tem para fazer e quantos dias (ex.: ''Rodrigo 2 dias''): eu marco." (as duas respondem); reestimar — só com a condição de agora (a pergunta que a revisão faria para a OS é a mesma: _agenda_gestor_perguntas_da_revisao seco; senão resolve e nada muda): 1 fico com os dias do dono (o prazo: "Sem resposta sobre Nelson até sex 30/10 às 18:00: fiquei com os 4 dias que você disse."; o dono: "Combinado, Nelson: fico com os 4 dias que você disse."); 2 os dias da conta ficam gravados com o sim do dono (estimativa_fonte orcamento, como a opção 1 das perguntas do P4; o histórico e a ação estimar, desfazível) e a agenda acompanha na hora (o corte dos últimos meios-dias do dono, _agenda_gestor_reestimar; ou o encaixe do que falta, _agenda_propor_e_aplicar de origem dono). O P12 recria esta função copiando DESTA migration. FASE 7 (7a P11, spec §5.11 e §6.3; AG7-15): a ficha_estimativa — 1) Mande: respondida ("Combinado: mando a ficha de ter 03/11 para Roberto."), a ficha sai na hora dela; 2) Segure: respondida ("Combinado: não mando a ficha de ter 03/11 para Roberto, nem a confirmação da manhã. Fale com Roberto."), a ficha e a confirmação desse dia ficam recusadas (veto); sem resposta até o prazo (via prazo, o passo vetos), vale a 1 e a pergunta fica resolvida ("sem resposta até sex 30/10 19:30: a ficha vai como eu disse"); a 2 nunca vale sem resposta.';

-- _agenda_linhas_do_fechamento (de 20261031100600_agenda_fase7a_rodada.sql)
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
  -- FASE 7: (7a P7) a linha do gestor em teste e a das compras da semana
  v_f7_txt   text;
  v_f7_cmp   jsonb;
  v_f7_min   date;
  v_f7_urg   boolean;
  v_f7_perda int;
  -- FASE 7: fim
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
      -- revisão da Fase 3 (item 5): o "vence hoje" de outro dia pelo ajudante único
      v_cob := public._agenda_vence_no_dia(regexp_replace(q.texto, '^[^—]* — saída [^.]*\.\s*', ''), q.dia, p_hoje);
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

  -- FASE 7: (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15) (l) a pergunta ficha_estimativa de hoje (a ficha de um dia pela minha
  -- estimativa, na janela de veto do ligar) numa linha própria, perda 75: ela perde hoje (a ficha das 19:30 só sai se o dono a
  -- viu) e não pode esperar a vaga da pergunta de fato (e), de perda 30, que não a repete. Uma linha por pessoa.
  for q in select x.* from public.agenda_perguntas x
            where x.tipo = 'ficha_estimativa' and x.estado = 'aberta' and x.veto_ate is not null
              and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje
              and x.mostrada_vezes < cf.perguntas_vezes_max
            order by x.veto_ate, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'pergunta', 'texto', 'Agenda: ' || q.texto, 'perda', 75, 'pergunta_id', q.id,
      'acao_ids', '[]'::jsonb, 'modo', case when q.modo = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end loop;
  -- FASE 7: fim
  -- (e) uma pergunta de fato, a que perde primeiro (cada pergunta aparece em até perguntas_vezes_max fechamentos)
  -- FASE 3: entram também concluir, entrega, equipe_resposta e diaria_ligar (não críticas)
  for m in select unnest(array['ligado', 'sombra']) loop
    select count(*) into v_n from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max;
    continue when v_n = 0;
    select x.* into q from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
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

  -- FASE 7: (7a P7) (i) o "eu marcaria assim" do gestor em teste (spec §6.1): com o modo marcar em sombra, o texto_sombra do
  -- diário de hoje (a rodada do gestor das 16:52 o grava), perda 65, com o modo da vigia (o dono lê de verdade o que o gestor
  -- faria). (j) As compras da semana (agenda_gestor_dia.compras de hoje, que o P10 grava, [{texto, compre_ate, urgente}]): perda
  -- 80 com alguma compra urgente (AG7-07: o serviço começa a menos de compra_urgente_du dias úteis — vai como decisão), 65 com
  -- "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis; sem nada disso, nenhuma linha. O modo é o do compre_ate.
  if public._agenda_gestor_modo('marcar') = 'sombra' then
    select g.texto_sombra into v_f7_txt from public.agenda_gestor_dia g where g.dia = p_hoje;
    if nullif(btrim(v_f7_txt), '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'gestor', 'texto', v_f7_txt, 'perda', 65, 'pergunta_id', null,
        'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  select g.compras into v_f7_cmp from public.agenda_gestor_dia g where g.dia = p_hoje;
  if jsonb_array_length(coalesce(v_f7_cmp, '[]'::jsonb)) > 0 then
    select min((e ->> 'compre_ate')::date), coalesce(bool_or((e ->> 'urgente')::boolean), false)
      into v_f7_min, v_f7_urg from jsonb_array_elements(v_f7_cmp) e;
    v_f7_perda := case when v_f7_urg then 80
                       when v_f7_min is not null and v_f7_min <= v_am1 then 65
                       when v_f7_min is not null and v_f7_min <= public.agenda_somar_du(p_hoje, cf.compras_aviso_du) then 45 end;
    v_f7_txt := array_to_string(array(select btrim(e ->> 'texto') from jsonb_array_elements(v_f7_cmp) with ordinality t(e, o)
                                       where nullif(btrim(e ->> 'texto'), '') is not null order by o), ' ');
    if v_f7_perda is not null and nullif(v_f7_txt, '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'compras', 'texto', public._agenda_corta('Compras: ' || v_f7_txt, c_max),
        'perda', v_f7_perda, 'pergunta_id', null, 'acao_ids', '[]'::jsonb,
        'modo', case when public._agenda_gestor_modo('compre_ate') = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  -- FASE 7: fim
  -- FASE 5: (h) a mensagem ao cliente, só com modo_cliente ligado: a que espera *manda cliente* e sai até o próximo dia de
  -- janela (perda 75; até 600 caracteres, c_max_cliente de _agenda_cliente_fechamento) e o que sai sozinho amanhã (perda 40,
  -- com *segura cliente*). As críticas (cliente_aviso) já entram pela linha decisao; o que saiu, pela linha mudancas.
  if cf.modo_cliente = 'ligado' then
    v_out := v_out || public._agenda_cliente_fechamento(p_hoje);
  end if;
  -- FASE 5: fim
  return coalesce((select jsonb_agg(x order by (x ->> 'perda')::int desc, x ->> 'tipo', x ->> 'texto')
                     from jsonb_array_elements(v_out) x), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_linhas_do_fechamento(date) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte.';

-- _agenda_modo_da_pergunta (de 20261031100000_agenda_fase7a_base.sql)
create or replace function public._agenda_modo_da_pergunta(p_tipo text, p_chave text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_tipo in ('nao_cabe', 'segundo_atraso', 'atraso_longo', 'remarcar_confirmado', 'fixada_pelo_dono') then c.modo_proposta
    when p_tipo = 'chegou' and coalesce(p_chave, '') like 'chegou:fornecedor:%' then c.modo_material
    -- CORREÇÃO 29/10 (revisão): a equipe sem dias é da vigia.
    when p_tipo = 'equipe_sem_dias' then c.modo_vigia
    -- CORREÇÃO 29/10 (revisão): fim
    when p_tipo in ('conferencia', 'chegou', 'parada', 'estouro', 'duracao', 'material_conferir', 'padrao_do_dono', 'entrega')
      then c.modo_vigia
    when p_tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
      then c.modo_material
    when p_tipo in ('diaria', 'diaria_ligar') then c.modo_diaria
    when p_tipo in ('equipe_resposta', 'concluir') then c.modo_equipe
    when p_tipo in ('cliente_aprovar', 'cliente_aviso', 'cliente_resposta') then c.modo_cliente
    when p_tipo = 'aprendizado' then c.modo_aprendizado
    -- FASE 7: (7a P11) a pergunta da ficha da equipe de um dia pela estimativa (ficha_estimativa) é das mensagens à equipe
    -- (modo_equipe), não do gestor que marca: a proteção vale enquanto houver dia marcado pela estimativa na janela, também com
    -- *gestor, só propor* (sem isso a pergunta nasceria em teste e a ficha ficaria segurada sem o dono poder soltá-la). Vem antes
    -- da linha do 7a P1, que ainda a cita.
    when p_tipo = 'ficha_estimativa' then c.modo_equipe
    -- FASE 7: fim
    -- FASE 7: os tipos do gestor da agenda (7a P1). O dia avisado e o prometido são críticas do plano, como o remarcar
    -- confirmado; a revisão diária faz reavaliar e reestimar; a cobrança do "compre até", a dela; o resto é do gestor que marca.
    when p_tipo in ('dia_avisado', 'dia_prometido') then c.modo_proposta
    when p_tipo in ('reavaliar', 'reestimar') then public._agenda_gestor_modo('revisao')
    when p_tipo = 'compre_ate' then public._agenda_gestor_modo('compre_ate')
    when p_tipo in ('situacao', 'estimativa', 'equipe_cadastro', 'ficha_estimativa', 'bem_livre', 'sinal', 'onda', 'sabado')
      then public._agenda_gestor_modo('marcar')
    -- FASE 7: fim
  end
    from public.agenda_config c
   where c.id;
$function$;

comment on function public._agenda_modo_da_pergunta(text, text) is
  'Agenda de Produção (correção de 29/10, P3): o modo de agenda_config de quem grava cada tipo de pergunta — críticas do plano: modo_proposta; conferencia, chegou, parada, estouro, duracao, material_conferir, padrao_do_dono, entrega: modo_vigia; chegou:fornecedor:…, nfe_vincular, pix_material, previsao_fornecedor, fornecedor_cadastro, fornecedores_prazo: modo_material; diaria, diaria_ligar: modo_diaria; equipe_resposta, concluir: modo_equipe; cliente_*: modo_cliente; aprendizado: modo_aprendizado; outro tipo: null. A limpeza da vigia fecha a pergunta aberta em sombra quando este modo está ligado. STABLE, invoker, só o service_role. CORREÇÃO 29/10 (revisão): o tipo novo equipe_sem_dias é da vigia (modo_vigia). Fase 7a (P1): dia_avisado e dia_prometido = modo_proposta (críticas do plano); reavaliar e reestimar = o modo da revisão do gestor; compre_ate = o da cobrança; situacao, estimativa, equipe_cadastro, ficha_estimativa, bem_livre, sinal, onda e sabado = o do gestor que marca (_agenda_gestor_modo). Fase 7a (P11): ficha_estimativa = modo_equipe (a pergunta é das mensagens à equipe: a proteção da ficha vale com *gestor, só propor*); o bloco vem antes da linha do P1, que ainda a cita.';

-- ── 3. Portas ──────────────────────────────────────────────────────────────────────────────────────────────────
-- As leituras novas (STABLE, invoker): authenticated (o foco e a tela leem com a RLS de quem pergunta) e service_role; nunca
-- anon (spec §3.1 item 10). O passo fichas escreve perguntas (pelo gravador definer do P4): sem grant a ninguém, nem
-- service_role (só a rodada do gestor o chama).
revoke all on function public._agenda_os_por_estimativa(uuid, date), public._agenda_os_compra_pendente(uuid, date),
  public._agenda_cliente_estimativa_liberada(text), public._agenda_ficha_liberada(uuid, date, timestamptz)
  from public, anon;
grant execute on function public._agenda_os_por_estimativa(uuid, date), public._agenda_os_compra_pendente(uuid, date),
  public._agenda_cliente_estimativa_liberada(text), public._agenda_ficha_liberada(uuid, date, timestamptz)
  to authenticated, service_role;
revoke all on function public._agenda_gestor_fichas(date, timestamptz) from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function
  public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid),
  public._agenda_rotina_ficha(date, timestamptz), public._agenda_rotina_como_foi(date, timestamptz),
  public._agenda_rotina_confirmar(date, timestamptz),
  public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public._agenda_linhas_do_fechamento(date) from public, anon;
grant execute on function public._agenda_linhas_do_fechamento(date) to authenticated, service_role;
revoke all on function public._agenda_modo_da_pergunta(text, text) from public, anon, authenticated;
grant execute on function public._agenda_modo_da_pergunta(text, text) to service_role;
