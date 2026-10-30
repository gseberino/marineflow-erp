-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P12 (7a-1): o sinal, o sábado e o orçamento grande.
-- O SINAL (AG7-09, "marco e cobro o sinal"): o sinal combinado e não pago não segura mais a OS — com a regra sinal_cobrar ela vai
-- à classe que teria sem ele (o compromisso, se o resto estiver pronto) e, quando ganha dia, o gestor lembra o dono de cobrar
-- ("Marquei Lenine (OS-00074) a partir de ter 03/11 e o sinal de R$ 2.000 ainda não entrou: cobre quando puder. Para o cliente
-- eu não digo nada sobre isso."); nada vai ao cliente. O SÁBADO (AG7-08, "sim, quando precisar"): só para cumprir um prazo firme
-- e sempre perguntando antes, com a pergunta crítica sabado ("Para Nelson ficar pronto até sex 13/11 (o que o cliente ouviu),
-- preciso do sábado 07/11 de manhã com Roberto. Sábado custa mais. 1) Use o sábado (recomendo); 2) Não use: o serviço termina
-- ter 17/11."); hoje ninguém tem o padrão de sábado, então é inerte. O ORÇAMENTO GRANDE enviado ou em rascunho: "se aprovar, cabe
-- a partir de …" no foco *agenda gestor*, sem ocupar ninguém.
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R1 AG7-09, §R3, §3.3 d9, §5.12, §6.2 item 6, §6.3 sinal e sabado, §8.4
-- agenda_fase7a_sinal_sabado.sql, §9 P12); nomes: fase7-registro.md §1 (_agenda_gestor_sinal, _agenda_gestor_sabado,
-- _agenda_gestor_orcamentos; sinal_cobrar; sabado_manha) e §2 (a cadeia de _agenda_classe_da_os, _agenda_gestor_decidir e
-- _agenda_gestor_sabado); respostas do dono: fase7-padroes.md (AG7-08, AG7-09).
-- Depende da 20261031100000 (7a P1: marcar_regras com sinal_cobrar, sabado_manha, simular_orcamento_*, os tipos sinal e sabado, o
-- diário agenda_gestor_dia), da 20261031100300 (7a P4: o gravador das perguntas e o despacho), da 20261031100400 (7a P5: o gancho
-- do sábado em _agenda_contexto e o validador), da 20261031100600 (7a P7: a rodada, que acha os passos sinal, sabado e
-- orcamentos, e o foco "Se aprovar:") e da 20261031100850 (7a P11: o despacho mais novo); antes delas, das Fases 1 a 6 e do lote
-- de 30/10 (agenda_encaixe_do_novo, 20261030100100).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (3 funções novas e 3 recriadas; nenhuma tabela, coluna, lista, dado, cron ou tela muda)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7a/p12/montar-migration.mjs: as 3 recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote e nas 20261031* dos
-- pacotes anteriores): _agenda_classe_da_os de 20261031100200 (7a P3), _agenda_gestor_decidir de 20261031100850 (7a P11) e
-- _agenda_validar_itens de 20261031100400 (7a P5). As mudanças estão só nos blocos "-- FASE 7: (7a P12 … -- FASE 7: fim"; fora
-- deles nenhuma linha muda (o S4 de supabase/tests/agenda_fase7a_sinal_sabado.sql confere). Sem a regra sinal_cobrar (o portão
-- _agenda_gestor_regra falso: o gestor fora de ligado, *gestor, só propor* ou a regra fora da lista) a classe é a de antes, byte a
-- byte; sem a variável agenda.sabado (só a decisão do sábado a liga), o validador é o de antes, byte a byte; o despacho só ganha o
-- ramo do tipo sabado.
--
-- POR QUE: AG7-09 — o dono respondeu "marco e cobro o sinal": o sinal pendente não pode deixar a OS sem data (nem na reserva).
-- AG7-08 — "sim, quando precisar": o sábado de manhã é exceção com custo, só para cumprir prazo firme, com o sim do dono. D7-3 —
-- o gestor considera também o que ainda vai ser aprovado: o orçamento grande mostra quando caberia, sem prender ninguém.
--
-- O QUE MUDA:
--   1. _agenda_classe_da_os (recriada): com a regra sinal_cobrar, a restrição sinal sai da trava "antes do material" e não entra
--      em condição nenhuma (condicao_tipo não ganha sinal; _agenda_condicao_da_reserva não muda): a OS fica na classe que teria.
--   2. _agenda_gestor_sinal (novo passo de todo tique): a pergunta sinal ao dono, uma por OS, quando a OS com o sinal pendente tem
--      dia de compromisso (sem opções, sem prazo); some sozinha quando o sinal entra. Nenhuma mensagem ao cliente.
--   3. _agenda_gestor_sabado (novo passo diário): com sabado_manha diferente de nunca e alguém com o padrão de sábado de manhã, a
--      OS com prazo firme que só fica pronta a tempo usando a manhã de sábado ganha a pergunta crítica sabado.
--   4. _agenda_gestor_decidir (recriada): o ramo sabado — 1) a variável agenda.sabado só na transação e o replano da OS (origem
--      dono); a manhã de sábado que entrou fica dita na disponibilidade da pessoa; 2) nada muda.
--   5. _agenda_validar_itens (recriada): com a variável, a manhã de sábado de quem tem o padrão não viola a regra 1.
--   6. _agenda_gestor_orcamentos (novo passo diário): os orçamentos grandes em aberto, a estimativa e o "cabe a partir de"
--      (agenda_encaixe_do_novo), no diário do gestor (agenda_gestor_dia.orcamentos), que o foco *agenda gestor* mostra.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_sinal_sabado.sql; registradas em notas-fase77a.md, P12):
--   · _agenda_validar_itens recriada (fora da spec e do registro, o aviso do P5): sem ela a decisão 1 do sábado faria o motor
--     levantar "a proposta saiu inválida" (a regra 1 lê a grade: "sábado só quando vocês combinam").
--   · A decisão 1 grava a manhã de sábado de quem vai como a exceção "vem" daquele sábado (agenda_disponibilidade, origem dono:
--     o sábado combinado, o mesmo dado que o 7b grava quando a pessoa oferece o sábado). Sem isso, a vigia seguinte leria a grade
--     ("sábado só quando vocês combinam"), veria a alocação como "quem ia não está mais livre" e tiraria o dia; a spec só dizia a
--     variável e o replano.
--   · O "se aprovar" reparte as diárias da estimativa pela equipe que o encaixe de um serviço novo usa sem gente dita
--     (equipe_sugerida pessoas por turno, o tamanho da dupla): "27,5 dias com 2 pessoas", como o texto da §6.2. Com a regra
--     uma_pessoa a estimativa da OS é de 1 pessoa, mas agenda_encaixe_do_novo (a conta que a spec manda usar) não simula 1 pessoa
--     sem nome.
--   · A pergunta sinal diz "está na agenda a partir de" quando o dia não foi o gestor quem marcou (o dono pediu), e omite o valor
--     quando o sinal não foi lançado (o orçamento esperando o sinal sem recebível).
--
-- ORDEM DE LIGAR (spec §10): nada liga aqui. O sinal e o "se aprovar" seguem o modo do gestor que marca (o passo sinal só pergunta
-- com ele ligado; o "se aprovar" em teste é a conta da sombra); o sábado, também (em teste a conta é seca), e só com alguém com o
-- padrão de sábado. Desfazer só o sinal: tirar sinal_cobrar de marcar_regras (a OS com o sinal pendente volta a esperar o sinal).
-- Desfazer só o sábado: sabado_manha = 'nunca'.
--
-- PROVA: supabase/tests/agenda_fase7a_sinal_sabado.sql (S0–S6), na bancada (node scripts/bancada-agenda/rodar.mjs).
--
-- APLICAR (depois do OK nomeado, com as 20261031100000–100850 já aplicadas):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100900_agenda_fase7a_sinal_sabado.sql
--
-- DESFAZER: reaplicar as definições de antes (as migrations de origem citadas acima, na ordem) e
--   drop function if exists public._agenda_gestor_sinal(date, timestamptz), public._agenda_gestor_sabado(date, timestamptz),
--     public._agenda_gestor_orcamentos(date, timestamptz);
--   (sem os passos, a rodada do gestor os pula: "ainda não existe"; as perguntas sinal e sabado abertas vencem sozinhas; o diário
--   agenda_gestor_dia.orcamentos fica como estava e sai do foco em 3 dias).
--
-- IDEMPOTENTE: create or replace function, comment, revoke e grant.

-- ── 1. As funções novas: os três passos da rodada do gestor (agenda_gestor_rodar, P7, os acha por to_regprocedure) ─────────

-- _agenda_gestor_sinal(p_hoje, p_agora): o passo sinal, em TODO tique (AG7-09 "marco e cobro o sinal").
create or replace function public._agenda_gestor_sinal(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_modo  text;
  v_cart  uuid[];
  v_pend  jsonb;
  v_res   int := 0;
  v_novas int := 0;
  v_lista jsonb := '[]'::jsonb;
  v_mot   text;
  v_txt   text;
  v_id    uuid;
  r       record;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_sinal: sem o dia ou a hora' using errcode = '22004';
  end if;
  -- a carteira e o sinal combinado e não pago (a mesma régua da restrição sinal de os_prontidao: o orçamento esperando o sinal
  -- sem nada pago, ou um sinal lançado e pendente; o valor é o pendente)
  select coalesce(array_agg(k.service_order_id), '{}'::uuid[]),
         coalesce(jsonb_object_agg(k.service_order_id::text, k.sinal_pendente)
                    filter (where (k.quote_status = 'awaiting_deposit' and k.sinal_pago = 0) or k.sinal_pendente > 0), '{}'::jsonb)
    into v_cart, v_pend
    from public.os_carteira(p_hoje) k;

  -- 1. a pergunta aberta que não vale mais some sozinha (em qualquer modo): o sinal entrou, a OS saiu da carteira ou não tem
  --    mais dia marcado
  for r in select q.id, q.service_order_id from public.agenda_perguntas q
            where q.tipo = 'sinal' and q.estado = 'aberta' order by q.criada_em, q.id loop
    v_mot := case when r.service_order_id is null or not (r.service_order_id = any (v_cart)) then 'a OS saiu da carteira'
                  when not v_pend ? r.service_order_id::text then 'o sinal entrou'
                  when not public._agenda_os_tem_dia(r.service_order_id, p_hoje) then 'a OS não está mais marcada na agenda' end;
    if v_mot is not null then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = v_mot where id = r.id;
      v_res := v_res + 1;
    end if;
  end loop;

  -- 2. a pergunta nova só com o gestor marcando de verdade e a regra (com a regra, o sinal não segura a OS: ela ganha dia)
  v_modo := coalesce(public._agenda_modo_da_pergunta('sinal', null), 'desligado');
  if v_modo <> 'ligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'o gestor não marca sozinho', 'modo', v_modo, 'resolvidas', v_res);
  end if;
  if not public._agenda_gestor_regra('sinal_cobrar') then
    return jsonb_build_object('pulado', true, 'motivo', 'a regra sinal_cobrar está fora', 'modo', v_modo, 'resolvidas', v_res);
  end if;
  for r in
    select k.service_order_id as os, k.numero, coalesce(k.cliente_curto, k.numero) as cliente, k.sinal_pendente as pend,
           (select min(a.dia) from public.agenda_alocacoes a
             where a.service_order_id = k.service_order_id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
               and a.dia >= p_hoje and a.resultado is distinct from 'nao_cumprido') as de,
           exists (select 1 from public.agenda_alocacoes a
                    where a.service_order_id = k.service_order_id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      and a.dia >= p_hoje and a.resultado is distinct from 'nao_cumprido' and a.origem = 'motor') as marquei
      from public.os_carteira(p_hoje) k
     where v_pend ? k.service_order_id::text and public._agenda_os_tem_dia(k.service_order_id, p_hoje)
     order by k.numero collate "C", k.service_order_id
  loop
    v_txt := case when r.marquei then format('Marquei %s (%s) a partir de %s', r.cliente, r.numero, public._dia_curto(r.de))
                  else format('%s (%s) está na agenda a partir de %s', r.cliente, r.numero, public._dia_curto(r.de)) end
             || ' e o sinal'
             || case when r.pend > 0
                     then ' de R$ ' || case when r.pend = trunc(r.pend) then replace(to_char(r.pend, 'FM999,999,990'), ',', '.')
                                            else translate(to_char(r.pend, 'FM999,999,990.00'), ',.', '.,') end
                     else '' end
             || ' ainda não entrou: cobre quando puder. Para o cliente eu não digo nada sobre isso.';
    v_id := public._agenda_gestor_perguntar('sinal', 'sinal:' || r.os, r.os, v_txt, '[]'::jsonb, null::smallint, null::timestamptz,
                                            null::smallint, v_modo, p_agora);
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

comment on function public._agenda_gestor_sinal(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P12; AG7-09 "marco e cobro o sinal", spec §5.12 e §6.3): o passo sinal da rodada do gestor, em todo tique. Com a regra sinal_cobrar o sinal combinado e não pago não segura a OS (_agenda_classe_da_os): ela ganha dia como as outras, e aqui o dono é lembrado de cobrar — para cada OS da carteira com o sinal pendente (o orçamento esperando o sinal sem nada pago, ou o sinal lançado e não pago: a régua da restrição sinal de os_prontidao) e com dia de compromisso de hoje em diante, a pergunta sinal (chave sinal:<os>, uma vez por OS, sem opções e sem prazo): "Marquei Lenine (OS-00074) a partir de ter 03/11 e o sinal de R$ 2.000 ainda não entrou: cobre quando puder. Para o cliente eu não digo nada sobre isso." (o dia marcado pelo dono: "Lenine (OS-00074) está na agenda a partir de …"; sem o valor lançado: "e o sinal ainda não entrou"). Só com o modo do gestor que marca ligado de verdade e a regra; senão {pulado}. A aberta some sozinha, em qualquer modo, quando o sinal entra ("o sinal entrou"), a OS sai da carteira ou não tem mais dia. Nenhuma mensagem ao cliente. {modo, perguntas, novas, resolvidas, os [{os, numero, pergunta_id, texto}]}. Invoker, sem grant (só a rodada do gestor o chama).';

-- _agenda_gestor_sabado(p_hoje, p_agora): o passo diário sabado (AG7-08: "sim, quando precisar" = só para cumprir prazo).
create or replace function public._agenda_gestor_sabado(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  v_modo   text;
  v_seco   boolean;
  v_sim    boolean := false;
  v_quem   int;
  v_hor    date;
  r        record;
  v_s0     jsonb;
  v_s1     jsonb;
  v_fim0   date;
  v_it     jsonb;
  v_sabs   date[];
  v_pes    text[];
  v_txt    text;
  v_ops    jsonb;
  v_chave  text;
  v_id     uuid;
  v_chaves text[] := '{}';
  v_lista  jsonb := '[]'::jsonb;
  v_cand   int := 0;
  v_novas  int := 0;
  v_res    int := 0;
  v_erros  int := 0;
  v_estado text;
  v_msg    text;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_sabado: sem o dia ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_modo := coalesce(public._agenda_modo_da_pergunta('sabado', null), 'desligado');
  if cf.sabado_manha = 'nunca' then
    v_modo := 'desligado';
  end if;
  v_seco := v_modo <> 'ligado';
  -- quem pode vir no sábado de manhã: a régua de _agenda_contexto (P5) — o padrão de sábado de manhã vigente
  v_quem := (select count(distinct d.payee_id) from public.agenda_disponibilidade d
              where d.payee_id is not null and d.substituida_em is null and d.dias_semana @> array[6]::smallint[]
                and d.situacao in ('disponivel', 'confirmada') and (d.turno is null or d.turno = 'manha'));
  v_hor := p_hoje + 7 * cf.horizonte_semanas;

  if v_modo <> 'desligado' and v_quem > 0 then
    -- em teste, a conta é a do gestor (a simulação da sombra), sem gravar nada
    if v_seco and coalesce(current_setting('agenda.gestor', true), '') <> 'sombra' then
      perform set_config('agenda.gestor', 'sombra', true);
      v_sim := true;
    end if;
    -- as OS com prazo firme (o que o cliente pediu: precisa_ate; o que ele ouviu: o prometido firme) no horizonte
    for r in
      select k.service_order_id as os, k.numero, coalesce(k.cliente_curto, k.numero) as cliente,
             least(pl.precisa_ate, case when pl.prometido_tipo = 'firme' then pl.prometido_ate end) as prazo,
             case when pl.prometido_tipo = 'firme' and pl.prometido_ate is not null
                       and (pl.precisa_ate is null or pl.prometido_ate <= pl.precisa_ate)
                  then 'o que o cliente ouviu' else 'o que o cliente pediu' end as rotulo
        from public.os_carteira(p_hoje) k
        join public.os_planejamento pl on pl.service_order_id = k.service_order_id
       where least(pl.precisa_ate, case when pl.prometido_tipo = 'firme' then pl.prometido_ate end) between p_hoje + 1 and v_hor
       order by 4, k.numero collate "C", k.service_order_id
    loop
      begin
        -- o fim que o motor dá sem o sábado: o compromisso novo dela (com o atraso, se houver), ou o da pergunta "não cabe";
        -- sem nada novo para ela (o plano que já tem fica) o sábado não muda nada; fora sem encaixe = não cabe
        v_s0 := public.agenda_propor('os', null, null, array[r.os], '{}'::jsonb, false, 'motor', null, p_hoje, p_agora);
        v_fim0 := (select max((i ->> 'fim_depois')::date) from jsonb_array_elements(coalesce(v_s0 -> 'itens', '[]'::jsonb)) i
                    where i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva' and (i ->> 'os')::uuid = r.os);
        if v_fim0 is null then
          v_fim0 := (select (o -> 'espera' ->> r.os::text)::date
                       from jsonb_array_elements(coalesce(v_s0 -> 'perguntas', '[]'::jsonb)) q, jsonb_array_elements(q -> 'opcoes') o
                      where q ->> 'tipo' = 'nao_cabe' and (q ->> 'service_order_id')::uuid = r.os and (o ->> 'n')::int = 1
                      limit 1);
          continue when v_fim0 is null
                        and not exists (select 1 from jsonb_array_elements(coalesce(v_s0 -> 'perguntas', '[]'::jsonb)) q
                                         where q ->> 'tipo' = 'nao_cabe' and (q ->> 'service_order_id')::uuid = r.os)
                        and not exists (select 1 from jsonb_array_elements(coalesce(v_s0 -> 'fora', '[]'::jsonb)) f
                                         where (f ->> 'os')::uuid = r.os and f ->> 'motivo' = 'sem_encaixe');
        end if;
        continue when v_fim0 is not null and v_fim0 <= r.prazo;
        v_cand := v_cand + 1;
        -- com a manhã de sábado de quem tem o padrão (a variável só aqui dentro)
        perform set_config('agenda.sabado', 'on', true);
        v_s1 := public.agenda_propor('os', null, null, array[r.os], '{}'::jsonb, false, 'motor', null, p_hoje, p_agora);
        perform set_config('agenda.sabado', '', true);
        select i into v_it from jsonb_array_elements(coalesce(v_s1 -> 'itens', '[]'::jsonb)) i
         where i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva' and (i ->> 'os')::uuid = r.os and i ->> 'critica' is null
           and (i ->> 'fim_depois')::date <= r.prazo
         order by (i ->> 'de')::date limit 1;
        continue when v_it is null;
        v_sabs := array(select distinct (a ->> 'dia')::date from jsonb_array_elements(v_it -> 'alocacoes') a
                         where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' order by 1);
        continue when cardinality(v_sabs) = 0;
        v_pes := array(select a ->> 'nome' from jsonb_array_elements(v_it -> 'alocacoes') with ordinality t(a, o)
                        where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno'
                        group by a ->> 'nome' order by min(o));
        v_txt := format('Para %s ficar pronto até %s (%s), preciso %s de manhã com %s. Sábado custa mais. 1) Use o sábado (recomendo); 2) Não use: %s.',
                        r.cliente, public._dia_curto(r.prazo), r.rotulo,
                        case when cardinality(v_sabs) = 1 then 'do sábado ' || to_char(v_sabs[1], 'DD/MM')
                             else 'dos sábados ' || public._agenda_lista(array(select to_char(x, 'DD/MM') from unnest(v_sabs) x order by x)) end,
                        public._agenda_lista(v_pes),
                        case when v_fim0 is not null then 'o serviço termina ' || public._dia_curto(v_fim0)
                             else 'sem o sábado, ele não cabe na agenda de agora' end);
        v_ops := jsonb_build_array(
          jsonb_build_object('n', 1, 'texto', 'Use o sábado',
                             'efeito', jsonb_build_object('sabado', true, 'sabados', to_jsonb(v_sabs), 'prazo', r.prazo,
                                                          'fim', v_it -> 'fim_depois')),
          jsonb_build_object('n', 2, 'texto', 'Não use: ' || case when v_fim0 is not null then 'o serviço termina ' || public._dia_curto(v_fim0)
                                                                   else 'sem o sábado, ele não cabe na agenda de agora' end,
                             'efeito', jsonb_build_object('nao_usar', true, 'fim', v_fim0)));
        v_chave := format('sabado:%s:%s', r.os, v_sabs[1]);
        v_chaves := v_chaves || v_chave;
        v_id := null;
        if not v_seco then
          v_id := public._agenda_gestor_perguntar('sabado', v_chave, r.os, v_txt, v_ops, 1::smallint, null::timestamptz,
                                                  null::smallint, v_modo, p_agora);
          if v_id is not null then
            -- a pergunta não vale depois que o sábado começa (crítica, sem prazo: só some)
            update public.agenda_perguntas set expira_em = lower(public.agenda_periodo(v_sabs[1], 'manha'))
             where id = v_id and estado = 'aberta' and expira_em > lower(public.agenda_periodo(v_sabs[1], 'manha'));
            if exists (select 1 from public.agenda_perguntas q where q.id = v_id and q.criada_em = p_agora) then
              v_novas := v_novas + 1;
            end if;
          end if;
        end if;
        v_lista := v_lista || jsonb_build_object('os', r.os, 'numero', r.numero, 'prazo', r.prazo, 'sabados', to_jsonb(v_sabs),
                                                 'pessoas', to_jsonb(v_pes), 'fim_sem', v_fim0, 'fim_com', v_it -> 'fim_depois',
                                                 'chave', v_chave, 'pergunta_id', v_id, 'texto', v_txt);
      exception when others then
        -- o erro de uma OS fica consultável e as outras seguem (o tempo da rodada, query_canceled, sobe)
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        perform public.log_app_error('db', format('gestor da agenda, passo sabado (%s): %s', r.numero, v_msg), 'agenda',
                                     'gestor:sabado', 'error',
                                     jsonb_build_object('os', r.os, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
      end;
    end loop;
    if v_sim then
      perform set_config('agenda.gestor', '', true);
    end if;
  end if;

  -- a pergunta aberta (de verdade) que esta conta não refez não vale mais: o plano mudou, o sábado passou ou ninguém vem mais
  if not v_seco or v_modo = 'desligado' then
    with f as (
      update public.agenda_perguntas q set estado = 'resolvida', resolvida_motivo = 'não precisa mais: o plano mudou'
       where q.tipo = 'sabado' and q.estado = 'aberta' and q.modo = 'ligado' and not (q.chave = any (v_chaves))
      returning 1)
    select count(*)::int into v_res from f;
  end if;
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'resolvidas', v_res,
                              'motivo', case when cf.sabado_manha = 'nunca' then 'sábado: nunca' else 'o gestor está desligado' end);
  end if;
  return jsonb_build_object('modo', v_modo, 'simulacao', v_seco, 'quem_vem_sabado', v_quem, 'candidatas', v_cand,
                            'perguntas', jsonb_array_length(v_lista), 'novas', v_novas, 'resolvidas', v_res, 'erros', v_erros,
                            'lista', v_lista);
end;
$function$;

comment on function public._agenda_gestor_sabado(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P12; AG7-08 "sim, quando precisar", spec §3.3 d9, §5.12 e §6.3): o passo diário sabado da rodada do gestor. Com sabado_manha diferente de nunca e alguém com o padrão de sábado de manhã: para cada OS da carteira com prazo firme no horizonte (least(precisa_ate, o prometido firme)) cujo fim, pelo motor sem o sábado (agenda_propor escopo os, sem gravar: o compromisso novo dela, a pergunta "não cabe" ou o "sem encaixe"), passa do prazo, a mesma conta com a variável agenda.sabado = on (a manhã de sábado de quem tem o padrão, _agenda_contexto do P5); se assim ela cabe no prazo usando a manhã de sábado, a pergunta crítica sabado (chave sabado:<os>:<o 1º sábado>; sem prazo; expira quando o sábado começa): "Para Nelson ficar pronto até sex 13/11 (o que o cliente ouviu), preciso do sábado 07/11 de manhã com Roberto. Sábado custa mais. 1) Use o sábado (recomendo); 2) Não use: o serviço termina ter 17/11." ("o que o cliente pediu" pelo precisa_ate). O modo é o do gestor que marca (_agenda_modo_da_pergunta): em teste a conta é a da sombra, seca (só na saída do passo); desligado ou sabado_manha = nunca = {pulado}. A aberta que a conta do dia não refaz é resolvida ("não precisa mais: o plano mudou"). O erro de uma OS vai a app_error_logs (gestor:sabado) e as outras seguem. Hoje ninguém tem o padrão de sábado: 0 perguntas. O 7b (P4) recria esta função para {pulado} com modo_sabado ligado. {modo, simulacao, quem_vem_sabado, candidatas, perguntas, novas, resolvidas, erros, lista}. Invoker, sem grant (só a rodada do gestor o chama).';

-- _agenda_gestor_orcamentos(p_hoje, p_agora): o passo diário orcamentos ("se aprovar, cabe a partir de").
create or replace function public._agenda_gestor_orcamentos(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_modo  text;
  v_sim   boolean := false;
  v_pes   int;
  v_d     jsonb;
  v_e     jsonb;
  v_dp    numeric;
  v_dias  numeric;
  v_cabe  text;
  v_txt   text;
  v_lista jsonb := '[]'::jsonb;
  v_sem   int := 0;
  r       record;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_orcamentos: sem o dia ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_modo := public._agenda_gestor_modo('marcar');
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'o gestor está desligado');
  end if;
  -- em teste, a estimativa e o encaixe são os do gestor (a simulação da sombra); nada é gravado no plano em nenhum modo
  if v_modo = 'sombra' and coalesce(current_setting('agenda.gestor', true), '') <> 'sombra' then
    perform set_config('agenda.gestor', 'sombra', true);
    v_sim := true;
  end if;
  -- o encaixe de um serviço novo sem gente dita usa equipe_sugerida pessoas por turno (agenda_encaixe_do_novo): as diárias da
  -- estimativa são repartidas por elas
  v_pes := greatest(cf.equipe_sugerida, 1);
  for r in
    select so.id, so.service_order_number as numero, so.grand_total as total,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cliente
      from public.service_orders so
      left join public.clients cl on cl.id = so.client_id
     where so.status = 'draft' and so.quote_status in ('draft', 'sent') and so.merged_into_id is null
       and so.grand_total >= cf.simular_orcamento_acima
       and (so.updated_at at time zone 'America/Sao_Paulo')::date >= p_hoje - cf.simular_orcamento_dias
     order by so.grand_total desc, so.service_order_number collate "C", so.id
  loop
    v_d := public.os_duracao_sugerida(r.id);
    if not coalesce((v_d ->> 'ok')::boolean, false) or coalesce((v_d ->> 'sem_base')::boolean, false)
       or coalesce((v_d ->> 'dp_realista')::numeric, 0) <= 0 then
      v_sem := v_sem + 1;
      continue;
    end if;
    v_dp := (v_d ->> 'dp_realista')::numeric;
    v_dias := greatest(0.5, round(v_dp / v_pes * 2) / 2);
    v_e := public.agenda_encaixe_do_novo(v_dias, '[]'::jsonb, null, p_hoje);
    v_cabe := case
      when coalesce((v_e ->> 'cabe')::boolean, false) and not coalesce((v_e ->> 'acima')::boolean, false)
        then 'cabe a partir de ' || public._dia_curto((v_e ->> 'de')::date)
      when coalesce((v_e ->> 'cabe')::boolean, false)
        then 'só acima da carga de sempre, a partir de ' || public._dia_curto((v_e ->> 'de')::date)
      when v_e ->> 'motivo' = 'sem_encaixe'
        then 'não cabe até ' || public._dia_curto((v_e ->> 'horizonte')::date) || ' com a equipe de agora'
      else 'não tenho com quem simular' end;
    v_txt := format('%s (%s, R$ %s): pela estimativa, %s com %s; %s.', r.cliente, r.numero,
                    replace(to_char(round(r.total), 'FM999,999,990'), ',', '.'), public._agenda_dias(v_dias),
                    case when v_pes = 1 then '1 pessoa' else v_pes || ' pessoas' end, v_cabe);
    v_lista := v_lista || jsonb_build_object('os', r.id, 'numero', r.numero, 'cliente', r.cliente, 'total', r.total,
                                             'dias', v_dias, 'pessoas', v_pes, 'diarias', v_dp,
                                             'cabe', coalesce((v_e ->> 'cabe')::boolean, false),
                                             'acima', coalesce((v_e ->> 'acima')::boolean, false),
                                             'cabe_de', v_e -> 'de', 'texto', v_txt);
  end loop;
  if v_sim then
    perform set_config('agenda.gestor', '', true);
  end if;
  perform public._agenda_gestor_dia_gravar(p_hoje, 'orcamentos', v_lista, p_agora);
  return jsonb_build_object('modo', v_modo, 'simulacao', v_sim, 'orcamentos', jsonb_array_length(v_lista), 'sem_base', v_sem,
                            'lista', v_lista);
end;
$function$;

comment on function public._agenda_gestor_orcamentos(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P12; spec §3 (l), §5.12 e §6.2 "Se aprovar:"): o passo diário orcamentos da rodada do gestor — os orçamentos grandes ainda em aberto (status draft, quote_status draft ou sent, sem agrupar, grand_total >= simular_orcamento_acima, mexidos nos últimos simular_orcamento_dias) com a estimativa pelas regras do gestor (os_duracao_sugerida: dp_realista) e o encaixe de um serviço novo sobre a grade de agora (agenda_encaixe_do_novo(dias, sem gente, sem presença dita, p_hoje), o P2 do lote de 30/10; nada é gravado no plano nem ocupa ninguém). Sem gente dita, o encaixe põe equipe_sugerida pessoas por turno: os dias são as diárias da estimativa repartidas por elas (meio dia em meio dia). Grava agenda_gestor_dia.orcamentos = [{os, numero, cliente, total, dias, pessoas, diarias, cabe, acima, cabe_de, texto}], do maior para o menor — o foco *agenda gestor* mostra "Se aprovar:" com cada texto: "Everton (ORÇ-00117, R$ 120.020): pela estimativa, 27,5 dias com 2 pessoas; cabe a partir de ter 17/11." (ou "só acima da carga de sempre, a partir de …", ou "não cabe até … com a equipe de agora"). O orçamento sem mão de obra separada fica de fora (sem_base). Em teste, a conta é a da sombra (a variável agenda.gestor só dentro do passo). Desligado = {pulado}. {modo, simulacao, orcamentos, sem_base, lista}. Invoker, sem grant (só a rodada do gestor o chama).';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7: (7a P12") ────────────────
-- Fora dos blocos nenhuma linha muda (o S4 de supabase/tests/agenda_fase7a_sinal_sabado.sql confere). Quem recriar de novo
-- qualquer uma delas copia DESTA migration (fase7-registro.md §2: _agenda_classe_da_os no 7g P5; _agenda_gestor_decidir, quem
-- acrescentar tipo do gestor; _agenda_validar_itens no 7b P4 e no 7e P4).

-- _agenda_classe_da_os (de 20261031100200_agenda_fase7a_prontidao.sql)
create or replace function public._agenda_classe_da_os(p_pront jsonb, p_meios jsonb, p_hoje date,
                                                       p_tem_fixada boolean default false,
                                                       p_fora_do_horizonte boolean default false)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_est   text := p_pront ->> 'estado';
  v_r     jsonb := coalesce(p_pront -> 'restricoes', '[]'::jsonb);
  v_mat   text := p_pront #>> '{material,estado}';
  v_crit  jsonb;
  v_trava jsonb;
  v_cond  text[] := '{}';
  v_txt   text;
  v_mat_trava boolean;
begin
  if not coalesce((p_pront ->> 'ok')::boolean, false) then
    return jsonb_build_object('classe', 4, 'motivo', 'nao_achei', 'texto', 'não encontrei esse serviço');
  end if;
  if v_est in ('concluida', 'fora_da_carteira') then
    return jsonb_build_object('classe', 4, 'motivo', 'fora_da_carteira', 'texto', p_pront ->> 'estado_texto');
  end if;
  if v_est = 'congelada' then
    return jsonb_build_object('classe', 4, 'motivo', 'congelada', 'texto', p_pront ->> 'estado_texto');
  end if;

  select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_crit
    from jsonb_array_elements(coalesce(p_pront #> '{material,itens}', '[]'::jsonb)) with ordinality t(e, o)
   where coalesce((e ->> 'critico')::boolean, true) and e ->> 'nivel' is distinct from 'A';

  -- Material que trava de vez (nem reserva): previsão vencida, ou falta sem previsão que não é compra já combinada.
  v_mat_trava := v_mat = 'atrasado'
     or (v_mat = 'sem_previsao' and exists (
           select 1 from jsonb_array_elements(v_crit) e
            where coalesce((e ->> 'sem_data')::boolean, false)
              and not (e ->> 'situacao' = 'falta' and coalesce((e ->> 'compra_prevista_em')::date >= p_hoje, false))));

  -- Em execução (ou com meio-dia fixado): compromisso primeiro, se o material deixa.
  if v_est in ('em_execucao', 'parada') or p_tem_fixada then
    if v_mat_trava then
      select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
       where e ->> 'tipo' in ('atrasado', 'sem_previsao', 'comprado_sem_previsao') order by o limit 1;
      return jsonb_build_object('classe', 4, 'motivo', 'material',
                                'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
    end if;
    -- FASE 7: (7a P3, regra situacao; AG7-11, §3.3 d6) a OS em andamento sem os dias ditos e sem plano (situacao_pendente de
    -- agenda_meios_da_os, só com a regra estimativa) também espera o "quanto falta?" antes de entrar no plano: sem isso, o motor
    -- a marcaria com a estimativa inteira (só a sugerida existe)
    if p_meios ->> 'situacao_pendente' = 'true' then
      return jsonb_build_object('classe', 4, 'motivo', 'situacao',
                                'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                    where e ->> 'tipo' = 'situacao' order by o limit 1), p_pront ->> 'estado_texto'));
    end if;
    -- FASE 7: fim
    return jsonb_build_object('classe', 1, 'motivo', case when p_tem_fixada then 'fixada' else 'em_execucao' end,
                              'texto', p_pront ->> 'estado_texto');
  end if;

  -- O que trava antes do material (quem destrava primeiro): orçamento, sinal, cliente, escopo; o bem ou o "não antes de"
  -- além do horizonte; depois o material que trava de vez.
  select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
   where e ->> 'tipo' in ('orcamento', 'sinal', 'cliente', 'escopo') order by o limit 1;
  -- FASE 7: (7a P12, regra sinal_cobrar; AG7-09 "marco e cobro o sinal", spec §R1 e §5.12) o sinal combinado e não pago não
  -- trava: a OS segue para a classe que teria sem ele (o compromisso, se o resto estiver pronto) — nada de reserva por sinal,
  -- e condicao_tipo não ganha 'sinal' — e o gestor lembra o dono de cobrar quando ela ganha dia (_agenda_gestor_sinal). O que
  -- trava depois do sinal na mesma lista (o orçamento, o cliente, o escopo) continua travando. Sem a regra, a de antes.
  if v_trava ->> 'tipo' = 'sinal' and public._agenda_gestor_regra('sinal_cobrar') then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('orcamento', 'cliente', 'escopo') order by o limit 1;
  end if;
  -- FASE 7: fim
  if v_trava is not null then
    return jsonb_build_object('classe', 4, 'motivo', v_trava ->> 'tipo', 'texto', v_trava ->> 'texto');
  end if;
  if p_fora_do_horizonte then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('bem', 'nao_antes') order by o limit 1;
    return jsonb_build_object('classe', 4, 'motivo', 'bem', 'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
  end if;
  if v_mat_trava then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('atrasado', 'sem_previsao', 'comprado_sem_previsao') order by o limit 1;
    return jsonb_build_object('classe', 4, 'motivo', 'material',
                              'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
  end if;
  -- FASE 7: (7a P3) o que o gestor não marca sem perguntar antes (as chaves de agenda_meios_da_os, que só existem com a regra
  -- estimativa): a OS começada ou parada (situacao_pendente, AG7-11) e a estimativa que ele não usa sozinho — acima de
  -- estimativa_max_diarias, com peça embutida ou sem mão de obra separada (estimativa_motivo, com a fonte ainda 'sugerida').
  -- Antes de "sem base para estimar" (que, sem a regra, continua 'duracao'); o P4 pergunta por estes dois motivos.
  if p_meios ->> 'situacao_pendente' = 'true' then
    return jsonb_build_object('classe', 4, 'motivo', 'situacao',
                              'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                  where e ->> 'tipo' = 'situacao' order by o limit 1), p_pront ->> 'estado_texto'));
  end if;
  if p_meios ->> 'estimativa_motivo' in ('grande', 'embutida', 'sem_base') and p_meios ->> 'fonte' = 'sugerida' then
    return jsonb_build_object('classe', 4, 'motivo', 'estimativa',
                              'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                  where e ->> 'tipo' = 'duracao' order by o limit 1),
                                                'quantos dias e com quem? (o orçamento não dá base para estimar)'));
  end if;
  -- FASE 7: fim
  if coalesce((p_meios ->> 'sem_base')::boolean, false) or (p_meios ->> 'total') is null then
    return jsonb_build_object('classe', 4, 'motivo', 'duracao',
                              'texto', 'quantos dias e com quem? (o orçamento não dá base para estimar)');
  end if;

  -- O que só deixa reservar (classe 3), do que mais trava ao que menos.
  if exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' = 'D' and e ->> 'situacao' = 'falta') then
    v_cond := v_cond || 'compra'::text;
  end if;
  -- FASE 7: (7a P3, regra compra_firme; D7-2, AG7-07) a peça a comprar com "compre até" (vivo ou gravado) abaixo do teto de
  -- empurrões não segura a OS na reserva: ela fica no compromisso e a compra é cobrada (o item vem marcado compra_firme pela
  -- os_prontidao). Só sai a condição quando TODA falta de nível D é firme.
  if 'compra' = any (v_cond) and public._agenda_gestor_regra('compra_firme')
     and not exists (select 1 from jsonb_array_elements(v_crit) e
                      where e ->> 'nivel' = 'D' and e ->> 'situacao' = 'falta'
                        and not coalesce((e ->> 'compra_firme')::boolean, false)) then
    v_cond := array_remove(v_cond, 'compra'::text);
  end if;
  -- FASE 7: fim
  if v_mat = 'sem_previsao'
     or exists (select 1 from jsonb_array_elements(v_crit) e
                 where e ->> 'nivel' = 'D' and e ->> 'situacao' in ('comprado', 'a_caminho')) then
    v_cond := v_cond || 'material'::text;
  end if;
  if v_mat = 'nao_conferido' then
    v_cond := v_cond || 'conferir_material'::text;
  end if;
  if p_meios ->> 'fonte' = 'sugerida' then
    v_cond := v_cond || 'duracao'::text;
  end if;
  if cardinality(v_cond) = 0 then
    return jsonb_build_object('classe', 2, 'motivo', 'pronta', 'texto', p_pront ->> 'estado_texto');
  end if;

  select e ->> 'texto' into v_txt from jsonb_array_elements(v_r) with ordinality t(e, o)
   where e ->> 'tipo' = any (case v_cond[1]
           when 'compra' then array['compre_ate', 'sem_previsao']
           when 'material' then array['compra_sem_prazo', 'comprado_sem_previsao', 'sem_previsao']
           when 'conferir_material' then array['peca_embutida', 'material_nao_conferido']
           else array['duracao'] end)
   order by o limit 1;
  return jsonb_build_object('classe', 3, 'motivo', v_cond[1], 'condicao_tipo', v_cond[1], 'condicoes', to_jsonb(v_cond),
                            'texto', coalesce(v_txt, p_pront ->> 'estado_texto'));
end;
$function$;

comment on function public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean) is
  'Agenda de Produção (Fase 2, P2): a classe da OS para o motor, pelas restrições de os_prontidao e o molde de agenda_meios_da_os — 1 = em execução/parada ou com meio-dia fixado (compromisso, primeiro); 2 = pronta: dias ditos ou aceitos, sem orçamento/sinal/cliente/escopo travando e todo crítico em A, B ou C (compromisso); 3 = o que falta é só compra (D falta, o "compre até"), material comprado sem previsão ou compra combinada sem prazo, conferir o material (zero linhas ou peça embutida) ou dias só sugeridos (só reserva condicionada; condicao_tipo na ordem compra > material > conferir_material > duracao); 4 = nunca: fora da carteira, em espera, material atrasado ou sem previsão, orçamento, sinal, cliente, escopo, o bem ou o "não antes de" além do horizonte, sem base para os dias. {classe, motivo, texto (quem trava), condicao_tipo}. FASE 7 (7a P3), com as chaves de agenda_meios_da_os que só existem com a regra estimativa: a OS começada ou parada (situacao_pendente; também a em andamento sem plano nem dias) = classe 4 situacao; a estimativa que o gestor não usa sozinho (estimativa_motivo grande, embutida ou sem_base, com a fonte sugerida) = classe 4 estimativa, antes do "sem base" (que sem a regra continua duracao); com a regra compra_firme, a falta de nível D com compra_firme (os_prontidao) não entra na condição compra (a OS fica no compromisso). Sem o portão, a de antes. FASE 7 (7a P12; AG7-09 "marco e cobro o sinal"): com a regra sinal_cobrar, o sinal combinado e não pago sai da trava de antes do material e não entra em condição nenhuma (condicao_tipo não ganha sinal): a OS fica na classe que teria sem ele (o compromisso, se o resto estiver pronto); o orçamento, o cliente e o escopo continuam travando. O gestor lembra o dono de cobrar (_agenda_gestor_sinal). Sem a regra, a de antes.';

-- _agenda_gestor_decidir (de 20261031100850_agenda_fase7a_protecoes.sql)
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
  -- FASE 7: (7a P12) o sábado de manhã para cumprir o prazo
  v_f12_sab  date;
  v_f12_r    jsonb;
  v_f12_x    record;
  v_f12_pes  text[];
  v_f12_sabs date[];
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
  -- FASE 7: (7a P12, spec §5.12 e §6.3; AG7-08) o sábado (crítica, sem prazo; a pergunta é do passo sabado):
  --   1) Use o sábado — a variável agenda.sabado só nesta transação (a manhã de sábado de quem tem o padrão de sábado vira útil
  --      no motor, _agenda_contexto do P5, e o validador a aceita) e o replano da OS, de origem dono (agenda_replanejar, "sábado
  --      autorizado"); a variável desliga logo depois. A manhã de sábado que entrou no plano fica dita na disponibilidade da
  --      pessoa (a exceção "vem" daquele sábado, origem dono: o sábado combinado — sem ela a grade diria "sábado só quando vocês
  --      combinam" e a vigia tiraria o dia como "quem ia não está mais livre"), e o texto lembra de combinar com quem vai (a
  --      ficha da equipe só sai para dia útil). O sábado que já começou não vale mais: a pergunta resolve e nada muda.
  --   2) Não use — respondida; nada muda (o atraso, se houver, é a crítica de sempre do motor).
  if v_q.tipo = 'sabado' then
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
    v_ef := coalesce(v_opc -> 'efeito', '{}'::jsonb);
    if not (v_ef ? 'sabado' or v_ef ? 'nao_usar') then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
    end if;
    select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) into v_nome
      from public.service_orders so left join public.clients cl on cl.id = so.client_id
     where so.id = v_q.service_order_id;
    if v_ef ? 'nao_usar' then
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id,
        'texto', format('Combinado: não uso o sábado para %s.', v_nome)
                 || case when v_ef ->> 'fim' is not null
                         then format(' O serviço termina %s.', public._dia_curto((v_ef ->> 'fim')::date)) else '' end);
    end if;
    v_f12_sabs := array(select x::date from jsonb_array_elements_text(coalesce(v_ef -> 'sabados', '[]'::jsonb)) x order by 1);
    v_f12_sab := v_f12_sabs[1];
    if v_f12_sab is null or lower(public.agenda_periodo(v_f12_sab, 'manha')) <= p_agora then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'o sábado já passou: nada mudou'
       where id = v_q.id;
      return jsonb_build_object('ok', false, 'gestor', true, 'sem_condicao', true,
        'texto', format('O sábado %s já passou: não mudei nada.', coalesce(to_char(v_f12_sab, 'DD/MM'), '')));
    end if;
    begin
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      perform set_config('agenda.sabado', 'on', true);
      v_f12_r := public.agenda_replanejar(array[v_q.service_order_id], 'sábado autorizado', 'dono', p_hoje, p_agora, p_autor);
      perform set_config('agenda.sabado', '', true);
      if not coalesce((v_f12_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0098', message = coalesce(v_f12_r ->> 'texto', 'não deu.');
      end if;
    exception when sqlstate 'P0098' then
      -- nada fica (nem a pergunta respondida nem a variável: a subtransação volta tudo)
      perform set_config('agenda.sabado', '', true);
      return jsonb_build_object('ok', false, 'gestor', true,
                                'texto', 'Não consegui usar o sábado: ' || sqlerrm || ' Nada mudou.');
    end;
    -- a manhã de sábado que entrou fica dita na disponibilidade de quem vai (a exceção "vem" daquele sábado, de manhã)
    v_f12_pes := '{}';
    v_f12_sabs := '{}';
    for v_f12_x in
      select a.payee_id, a.dia, public._agenda_nome_curto(py.name) as nome
        from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
       where a.service_order_id = v_q.service_order_id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
         and a.presenca = 'turno' and a.turno = 'manha' and extract(isodow from a.dia) = 6 and a.dia >= p_hoje
         and a.resultado is null
       group by a.payee_id, a.dia, py.name
       order by a.dia, 3, a.payee_id
    loop
      if not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = v_f12_x.payee_id and d.substituida_em is null and d.periodo @> v_f12_x.dia
                        and d.situacao in ('disponivel', 'confirmada') and (d.turno is null or d.turno = 'manha')) then
        insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, trecho, criado_por)
        values (v_f12_x.payee_id, daterange(v_f12_x.dia, v_f12_x.dia, '[]'), 'manha', 'disponivel', 'dono',
                left(format('sábado de manhã para %s: você autorizou', public._agenda_rotulo_da_os(v_q.service_order_id)), 200),
                left(p_trecho, 300), p_autor);
      end if;
      if not (v_f12_x.nome = any (v_f12_pes)) then v_f12_pes := v_f12_pes || v_f12_x.nome; end if;
      if not (v_f12_x.dia = any (v_f12_sabs)) then v_f12_sabs := v_f12_sabs || v_f12_x.dia; end if;
    end loop;
    if cardinality(v_f12_sabs) = 0 then
      return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id, 'agenda', v_f12_r,
        'texto', 'Refiz a conta com o sábado liberado, mas ele não entrou: ' || coalesce(nullif(v_f12_r ->> 'texto', ''), 'nada mudou.'));
    end if;
    return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id, 'agenda', v_f12_r,
      'sabados', to_jsonb(v_f12_sabs),
      'texto', format('Combinado: uso %s de manhã para %s.', case when cardinality(v_f12_sabs) = 1
                                                                  then 'o sábado ' || to_char(v_f12_sabs[1], 'DD/MM')
                                                                  else 'os sábados ' || public._agenda_lista(array(
                                                                         select to_char(x, 'DD/MM') from unnest(v_f12_sabs) x order by x))
                                                             end, v_nome)
               || coalesce(' ' || nullif(v_f12_r ->> 'texto', ''), '')
               || format(' Combine o sábado com %s: a ficha da equipe só sai para dia útil.', public._agenda_lista(v_f12_pes)));
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
  'Agenda de Produção (Fase 7a, P4): o despacho das perguntas do gestor (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal), chamado por agenda_decidir (o dono) e por _agenda_gestor_vetos (p_via prazo). Só situacao e estimativa decidem aqui (os outros tipos: "não tem opções" ou "ainda não sei decidir", até os pacotes P8, P9, P11 e P12 recriarem ESTA função). Opção com efeito dias: se a pergunta que o gestor faria agora para a OS ainda é esta, grava os dias (_agenda_gestor_gravar_dias; a pergunta respondida pelo dono, ou resolvida "sem resposta até sex 30/10 18:00: ficou como eu disse"); senão resolve a pergunta e nada muda. dizer: fica aberta com a escolha (o prazo não vale mais), "Me diga os dias (ex.: ''Nelson 3 dias'')."; terminou: "Use *concluiu Nelson*."; nao_fazer: "não marco". Só com a pergunta e o modo de quem a fez ligados. Trava agenda_plano. {ok, gestor true, texto, acao_id?, aberta?, sem_condicao?}. Security definer, sem grant a ninguém. FASE 7 (7a P8, spec §5.8): a onda — com a agenda na mesma versão do plano da pergunta, a conta é refeita pelo motor com os parâmetros da proposta dela (agenda_propor persistido, criada_por dono) e aplicada com a pergunta (ações críticas): 1 tudo ("Feito: …"); 2 só as OS de evento real, o de hoje e amanhã (sem nenhuma: "Não havia nada de hoje e amanhã para mudar: não mudei nada."); 3 nada (a proposta descartada; "Combinado: não mudei nada. …"). Com a agenda mudada desde a pergunta, a pergunta resolve e nada muda ("A agenda mudou desde a pergunta: …"). Falhou = nada fica, a pergunta continua aberta. Sem prazo (via prazo: "Essa pergunta não tem prazo"). O P9 e o P12 recriam esta função copiando DESTA migration. FASE 7 (7a P9, spec §5.9 e §6.3): reavaliar (sem prazo) — 1 "Use *concluiu Rodrigo*."; 2 "Me diga o que mais tem para fazer e quantos dias (ex.: ''Rodrigo 2 dias''): eu marco." (as duas respondem); reestimar — só com a condição de agora (a pergunta que a revisão faria para a OS é a mesma: _agenda_gestor_perguntas_da_revisao seco; senão resolve e nada muda): 1 fico com os dias do dono (o prazo: "Sem resposta sobre Nelson até sex 30/10 às 18:00: fiquei com os 4 dias que você disse."; o dono: "Combinado, Nelson: fico com os 4 dias que você disse."); 2 os dias da conta ficam gravados com o sim do dono (estimativa_fonte orcamento, como a opção 1 das perguntas do P4; o histórico e a ação estimar, desfazível) e a agenda acompanha na hora (o corte dos últimos meios-dias do dono, _agenda_gestor_reestimar; ou o encaixe do que falta, _agenda_propor_e_aplicar de origem dono). O P12 recria esta função copiando DESTA migration. FASE 7 (7a P11, spec §5.11 e §6.3; AG7-15): a ficha_estimativa — 1) Mande: respondida ("Combinado: mando a ficha de ter 03/11 para Roberto."), a ficha sai na hora dela; 2) Segure: respondida ("Combinado: não mando a ficha de ter 03/11 para Roberto, nem a confirmação da manhã. Fale com Roberto."), a ficha e a confirmação desse dia ficam recusadas (veto); sem resposta até o prazo (via prazo, o passo vetos), vale a 1 e a pergunta fica resolvida ("sem resposta até sex 30/10 19:30: a ficha vai como eu disse"); a 2 nunca vale sem resposta. FASE 7 (7a P12, spec §5.12 e §6.3; AG7-08): o sábado (crítica, sem prazo) — 1) Use o sábado: a variável agenda.sabado só na transação (a manhã de sábado de quem tem o padrão no motor e no validador) e agenda_replanejar(a OS, "sábado autorizado", dono); a manhã de sábado que entrou fica dita na disponibilidade de quem vai (a exceção "vem" daquele sábado, origem dono) e o texto lembra de combinar ("… Combine o sábado com Roberto: a ficha da equipe só sai para dia útil."); o sábado que já começou resolve a pergunta e nada muda; falhou = nada fica; 2) Não use: respondida, nada muda ("Combinado: não uso o sábado para Nelson. O serviço termina ter 17/11."). Sem prazo (via prazo: "Essa pergunta não tem prazo"). Quem recriar esta função depois copia DESTA migration.';

-- _agenda_validar_itens (de 20261031100400_agenda_fase7a_teto.sql)
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

  -- FASE 7: (7a P12, spec §3.3 d9 e §5.12; AG7-08) a manhã de sábado que o dono autorizou: a decisão 1 da pergunta crítica
  -- sabado liga a variável agenda.sabado só na transação dela, e o motor (_agenda_contexto, P5) passa a contar a manhã de sábado
  -- de quem tem o padrão de sábado. Aqui a mesma conta: com a variável e sabado_manha diferente de 'nunca', o meio-dia de turno
  -- na manhã de um sábado sem feriado, de quem tem o padrão de sábado de manhã (linha vigente com dias_semana contendo o sábado,
  -- de manhã ou o dia todo, vem) e que a grade dá como fim de semana (sem exceção "não vem" nem recesso: aí ela diz
  -- indisponivel), não viola a regra 1. Sem a variável, a regra 1 de antes (o T6d do agenda_fase7a_teto continua recusando).
  if coalesce(current_setting('agenda.sabado', true), '') = 'on' and cf.sabado_manha <> 'nunca' and jsonb_array_length(v_v) > 0 then
    v_v := coalesce((
      select jsonb_agg(e order by o) from jsonb_array_elements(v_v) with ordinality t(e, o)
       where not (e ->> 'regra' = '1' and exists (
         select 1
           from jsonb_to_recordset(v_n) as n(os uuid, payee_id uuid, nome text, dia date, turno text, presenca text)
           join jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, turno text, situacao text)
             on k.payee_id = n.payee_id and k.dia = n.dia and k.turno = n.turno
          where n.os::text = e ->> 'os' and n.nome is not distinct from e ->> 'pessoa' and n.dia::text = e ->> 'dia'
            and n.turno = e ->> 'turno' and n.presenca = 'turno' and n.turno = 'manha' and extract(isodow from n.dia) = 6
            and k.situacao = 'fim_de_semana' and public.agenda_feriado(n.dia) is null
            and exists (select 1 from public.agenda_disponibilidade d
                         where d.payee_id = n.payee_id and d.substituida_em is null and d.dias_semana @> array[6]::smallint[]
                           and d.situacao in ('disponivel', 'confirmada') and (d.turno is null or d.turno = 'manha'))))),
      '[]'::jsonb);
  end if;
  -- FASE 7: fim
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
  'Agenda de Produção (Fase 2, P2): as 14 regras duras sobre os itens (criar e cancelar) de uma proposta, contra o banco de agora — (1) pessoa ativa e livre no turno (a ponta livre na presença curta, sem compromisso com hora), sem feriado; (2) sem choque com o vigente nem dentro da proposta; (3) não antes do dia em que fica pronta; (4) a presença do dono conforme a regra; (5) alguém em cada meio-dia; (6) o teto por pessoa e semana; (7) nada no congelado (salvo evento real e pedido do dono) nem no que começou; (8) o fixado só sai autorizado; (9) a OS na carteira; (10) classe 4 nunca; (11) reserva condicionada não vira compromisso; (12) wip_max por meio-dia; (13) no máximo interrupcoes_max dias parados; (14) com p_aplicar, item crítico só com a pergunta respondida. Lista vazia = ok; cada violação {regra, os, numero, pessoa, dia, turno, texto}. FASE 6 (P4): a regra 6 usa a carga de cada pessoa (_agenda_carga_da_pessoa: o dono com capacidade_dono em uso; os outros, carga_max) no lugar de carga_max; o texto não muda. FASE 7 (7a P5), atrás do portão _agenda_gestor_regra(''teto_equipe''): a regra 6 faz a conta do encaixe — o compromisso de cada pessoa da equipe até 100% do esperado (o dono com o teto dele; a semana inteira com as reservas e o texto não mudam) e, por semana, a soma da equipe (as pessoas da grade menos o dono; o vigente menos o cancelado + o novo, sem reserva e sem o pedido do dono) até floor(carga_max × a soma do esperado dela): "A equipe passaria do limite da semana de 09/11: 11 meios-dias de serviço para 10." (pessoa nula). Só confere a semana com compromisso novo da equipe fora do pedido do dono; com acima_da_carga, sem a conta da equipe. Sem o portão, a regra 6 da Fase 6. FASE 7 (7a P12; AG7-08): com a variável agenda.sabado = on (só a decisão 1 da pergunta crítica sabado a liga, na transação dela) e sabado_manha diferente de nunca, o meio-dia de turno na manhã de um sábado sem feriado, de quem tem o padrão de sábado de manhã e que a grade dá como fim de semana, não viola a regra 1 (a mesma conta do gancho do sábado de _agenda_contexto). Sem a variável, a de antes.';

-- ── 3. Portas ──────────────────────────────────────────────────────────────────────────────────────────────────
-- Os três passos escrevem perguntas (pelo gravador definer do P4) ou o diário do gestor (pelo gravador definer do P1): sem grant
-- a ninguém, nem service_role (só a rodada do gestor, definer, os chama). Nunca anon (spec §3.1 item 10).
revoke all on function public._agenda_gestor_sinal(date, timestamptz), public._agenda_gestor_sabado(date, timestamptz),
  public._agenda_gestor_orcamentos(date, timestamptz)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean) from public, anon;
grant execute on function public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean) to authenticated, service_role;
revoke all on function public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb) from public, anon;
grant execute on function public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb) to authenticated, service_role;
revoke all on function public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)
  from public, anon, authenticated, service_role;
