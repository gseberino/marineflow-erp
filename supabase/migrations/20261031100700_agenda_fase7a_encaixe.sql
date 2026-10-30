-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P8 (7a-1): o encaixe na aprovação, a onda e a zona travada.
-- O orçamento aprovado (o sinal pago, a OS que o agrupar criou, a assinatura) ganha data, pergunta ou motivo no tique seguinte do
-- gestor (até 15 min); uma rodada que mudaria muita coisa de uma vez para e pergunta; e o dia que a equipe já recebeu na ficha ou
-- que o cliente já ouviu só muda com o sim do dono.
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R, §3.2, §5.8, §6.3, §8.3 C, §8.4); nomes: fase7-registro.md §1 e §2;
-- respostas do dono: fase7-padroes.md (D7-3: encaixa assim que o orçamento é aprovado; AG7-15: o dia avisado ao cliente sempre
-- espera o dono).
-- Depende da 20261031100000 (7a P1: os modos, gestor_k_os, gestor_k_dias_avisados, os tipos onda/dia_avisado/dia_prometido e o
-- portão), da 20261031100200 (7a P3: agenda_propor e a recomendação das críticas da zona), da 20261031100300 (7a P4: as perguntas
-- do gestor e o despacho) e da 20261031100600 (7a P7: a rodada, que acha o passo encaixe por to_regprocedure); antes delas, das
-- Fases 1 a 6 e do lote de correção de 30/10, todos em produção.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (4 funções novas e 5 recriadas; nenhuma tabela, coluna, lista, dado, cron ou tela muda)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7a/p8/montar-migration.mjs: as 5 recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote e nas 20261031* dos
-- pacotes anteriores): _agenda_criticidade de 20261025100200, _agenda_criticidade_da_acao e _agenda_propor_e_aplicar de
-- 20261025100300, agenda_propor de 20261031100200 (7a P3) e _agenda_gestor_decidir de 20261031100300 (7a P4). As mudanças estão
-- só nos blocos "-- FASE 7: … -- FASE 7: fim"; fora deles nenhuma linha muda (o E6 de supabase/tests/agenda_fase7a_encaixe.sql
-- confere). Com o portão do gestor falso (a regra zona_travada / onda fora, o gestor desligado, em sombra fora da simulação ou com
-- *gestor, só propor*), a saída das recriadas é a de antes, byte a byte (E6 também).
--
-- POR QUE: em 29/10 a vigia rodou 94 vezes sem encaixar nada; fora da quinta ela só encaixa o que virou classe 2 (D7-3: o gestor
-- encaixa o serviço assim que o orçamento é aprovado). E um gestor que marca sozinho precisa de freio: mexer no dia que a equipe já
-- sabe ou que o cliente já ouviu, ou mudar muita coisa de uma vez (a falta de alguém em 3 OS), é do dono decidir (spec §3.2).
--
-- O QUE MUDA:
--   1. _agenda_gestor_encaixe (o passo encaixe da rodada do gestor, a cada tique 07/22/37/52): as OS da carteira sem dia de
--      compromisso, com algo novo desde a marca d'água (a conversão em OS — converted_to_os_at, que o gatilho do sinal grava e o
--      agrupar também, sem status_change —, a assinatura, o status_change para open/approved/scheduled, o planejamento ou o
--      material mudados, os dias que o prazo vencido do mesmo tique gravou), não tentadas pela vigia. Ligado: o motor encaixa
--      (_agenda_propor_e_aplicar, origem vigia, a onda vale) e as que ficaram de fora ganham a pergunta do gestor. Em teste: o
--      mesmo motor com as regras ligadas só ali dentro, no diário (agenda_gestor_dia.sombra.encaixe). A contagem por OS ("da
--      aprovação ao 1º dia marcado") vai em agenda_vigia_rodadas.contagens.encaixe. handle_quote_deposit_payment NÃO muda.
--   2. A onda (_agenda_gestor_onda_conta, _agenda_gestor_onda e o bloco de _agenda_propor_e_aplicar): na rodada da vigia/gestor,
--      mais de gestor_k_os (2) OS com dia mudado, ou mais de gestor_k_dias_avisados (1) dia já avisado mexido, não aplica: a
--      proposta fica aberta e nasce a pergunta crítica onda ("Mudou muita coisa de uma vez (Roberto não vem): eu mudaria 3
--      serviços (…) e 1 dia que a equipe já sabia. Não fiz nada ainda. 1) Faço tudo como montei (recomendo; *agenda plano*
--      mostra); 2) Mudo só o de hoje e amanhã; 3) Não mudo nada: você me diz."). A reserva promovida, a OS nova e a troca de
--      pessoa no mesmo meio-dia não contam.
--   3. A zona travada (_agenda_criticidade, _agenda_zona_fora e agenda_propor): o fim que passaria do prometido firme ao cliente,
--      e o meio-dia de um dia já dito ao cliente (dia_prometido) ou à equipe (dia_avisado) que sairia sem ter ficado impossível,
--      viram pergunta crítica (a recomendação do P3: "A equipe já tinha recebido a ficha desse dia: recomendo seguir e você
--      avisar quem ia" / "É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje"); a decisão é a crítica de
--      sempre (agenda_decidir). _agenda_criticidade_da_acao reconfere sobre a ação executada (a saúde: dia_avisado_sem_pergunta e
--      zona_travada_mexida, do P7, ficam vivos).
--   4. _agenda_gestor_decidir (recriada): a onda — 1 refaz a conta (a mesma versão do plano) e aplica tudo; 2 só o de hoje e
--      amanhã (as OS de evento real); 3 descarta. Com a agenda mudada desde a pergunta, resolve e a rodada seguinte refaz.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_encaixe.sql; registradas em notas-fase77a.md, P8):
--   · agenda_propor é recriada (fora da spec): o motor passava p_violadas vazio a _agenda_criticidade, e a zona travada precisa
--     saber o que ficou impossível; com a regra, ele passa _agenda_zona_fora (função nova). O meio-dia fixado pelo dono nunca fica
--     fora, para a regra 3 (fixada_pelo_dono) continuar a de antes. Fora a violação, ficam fora da conta o resto do meio-dia dela
--     e o que volta igual no encaixe novo (a mesma pessoa no mesmo meio-dia: para ela nada muda).
--   · O cancelamento do que não pode mais acontecer continua entrando na hora, como em toda crítica desde a Fase 2: o que espera o
--     dono é o encaixe novo da OS. _agenda_criticidade_da_acao conta a zona só nas ações que marcaram meios-dias.
--   · A onda é pergunta da versão do plano (onda:v<versão>): a mesma conta não pergunta duas vezes, e o "não mudo nada" vale até
--     a agenda mudar. A decisão refaz a conta pelo motor (a proposta da pergunta pode ter sido refeita pela vigia na mesma versão).
--   · Os vetos do mesmo tique entram nas candidatas pela ação estimar que gravaram (o passo não recebe a saída do anterior).
--
-- ORDEM DE LIGAR (spec §10): nada liga aqui. O encaixe roda com modo_encaixe_aprovacao (a migration de dado 20261031100990 o põe em
-- sombra; o "OK ligar o encaixe na aprovação" o liga); a onda e a zona travada são regras do gestor que marca (marcar_regras, com
-- modo_marcar_sozinho ligado). Desfazer: o modo para sombra; a regra fora de marcar_regras; *gestor, só propor*.
--
-- PROVA: supabase/tests/agenda_fase7a_encaixe.sql (E0–E6) e o cenário C de agenda_fase7a_replay.sql, na bancada
-- (node scripts/bancada-agenda/rodar.mjs).
--
-- APLICAR (depois do OK nomeado, com as 20261031100000–100600 já aplicadas):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100700_agenda_fase7a_encaixe.sql
--
-- DESFAZER: reaplicar as definições de antes (as migrations de origem citadas acima, na ordem) e
--   drop function if exists public._agenda_gestor_encaixe(date, timestamptz), public._agenda_gestor_onda(uuid, date, timestamptz),
--     public._agenda_gestor_onda_conta(jsonb), public._agenda_zona_fora(jsonb, uuid, jsonb);
--   (sem o passo encaixe, a rodada do gestor o pula: "ainda não existe").

-- ── 1. As funções novas ────────────────────────────────────────────────────────────────────────────────────────

-- A zona travada no motor (spec §3.2 e §5.8): das alocações que a proposta tira de uma OS (v_canc de agenda_propor, as entradas
-- de _agenda_violacoes e do pedido do dono), as que ficam FORA da conta do dia já avisado — o que não pode mais acontecer (a
-- violação: a pessoa não vem, o material, o cliente, a OS saiu), o resto do meio-dia de uma violada (o mesmo dia e turno da mesma
-- OS: cai junto com ela) e o que volta igual no encaixe novo (a mesma pessoa, o mesmo meio-dia e a mesma presença: para ela nada
-- muda). O meio-dia fixado pelo dono nunca fica fora (a regra 3 de _agenda_criticidade continua a de antes: qualquer fixado que
-- sai pergunta). É o p_violadas de _agenda_criticidade com a regra zona_travada; o resto (o que muda sem ter ficado impossível)
-- é o que a regra confere contra _agenda_dia_avisado.
create or replace function public._agenda_zona_fora(p_canc jsonb, p_os uuid, p_novas jsonb)
 returns uuid[]
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(array_agg(distinct (c ->> 'alocacao_id')::uuid), '{}'::uuid[])
    from jsonb_array_elements(coalesce(p_canc, '[]'::jsonb)) c
   where (c ->> 'os')::uuid = p_os
     and not (coalesce(c ->> 'estado', '') = 'fixada' and coalesce(c ->> 'fixado_por', '') = 'dono')
     and (coalesce((c ->> 'violada')::boolean, false)
          or exists (select 1 from jsonb_array_elements(p_canc) v
                      where (v ->> 'os')::uuid = p_os and coalesce((v ->> 'violada')::boolean, false)
                        and v ->> 'dia' = c ->> 'dia' and v ->> 'turno' = c ->> 'turno')
          or exists (select 1 from jsonb_array_elements(coalesce(p_novas, '[]'::jsonb)) n
                      where n ->> 'payee_id' = c ->> 'payee_id' and n ->> 'dia' = c ->> 'dia' and n ->> 'turno' = c ->> 'turno'
                        and coalesce(n ->> 'presenca', 'turno') = coalesce(c ->> 'presenca', 'turno')));
$function$;

comment on function public._agenda_zona_fora(jsonb, uuid, jsonb) is
  'Agenda de Produção (Fase 7a, P8; spec §3.2 e §5.8): das alocações que a proposta tira da OS p_os (as entradas de cancelamento do motor, p_canc), as que ficam fora da conta do dia já avisado da zona travada — a violada (não pode mais acontecer), o resto do meio-dia de uma violada e a que volta igual em p_novas (as alocações do encaixe novo da OS: a mesma pessoa, dia, turno e presença). O fixado pelo dono nunca fica fora (a regra 3 de _agenda_criticidade não muda). É o p_violadas que agenda_propor passa a _agenda_criticidade com a regra zona_travada. IMMUTABLE; só o service_role.';

-- A conta da onda (spec §3.2 e §5.8) sobre os itens de uma proposta do motor, só com o que o aplicar faria sem perguntar (os
-- itens não críticos: _agenda_itens_escolhidos sem lista nem pergunta) e só das OS sem item crítico (a OS que já virou pergunta
-- crítica — a zona travada, o atraso, o nao_cabe — fica fora da conta: o dono já decide sobre ela, e a onda seria a 2ª pergunta).
--   (a) As OS com dia mudado: tinham compromisso vigente que sai (o cancelar que não é a reserva virando compromisso) e ganham
--       meios-dias (o criar), e algum meio-dia delas que sai não volta no encaixe novo. A troca de pessoa no mesmo meio-dia não
--       conta; a OS nova (nada a cancelar) e a reserva promovida também não.
--   (b) Os dias já avisados que a proposta mexe: o dia de cada meio-dia de compromisso que sai e não volta igual (a mesma pessoa,
--       o mesmo meio-dia), com _agenda_dia_avisado (a equipe já recebeu a ficha; o cliente já ouviu o dia — este vence). Conta-se
--       o dia (um "não vem" de amanhã que tira duas pessoas do mesmo dia é 1 dia).
--   (c) O porquê, pelo que saiu sem poder acontecer (a violação com mais meios-dias): quem não vem, o material, o cliente.
-- {os, os_n, nomes, dias [{dia, quem}], dias_n, equipe_n, cliente_n, motivo, evento_real, perda_em}.
create or replace function public._agenda_gestor_onda_conta(p_itens jsonb)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_crit  uuid[] := array(select distinct (i ->> 'os')::uuid from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) i
                           where i ->> 'critica' is not null);
  v_sel   jsonb := (select coalesce(jsonb_agg(i order by k), '[]'::jsonb)
                      from jsonb_array_elements(public._agenda_itens_escolhidos(coalesce(p_itens, '[]'::jsonb), null, null))
                           with ordinality t(i, k)
                     where not ((i ->> 'os')::uuid = any (v_crit)));
  v_os    uuid[];
  v_dias  jsonb;
  v_nomes text[];
  v_mot   text;
  v_quem  text[];
  v_ev    uuid[];
  v_perda date;
begin
  with
  canc as (
    select (i ->> 'os')::uuid as os, x ->> 'payee_id' as payee, x ->> 'dia' as dia, x ->> 'turno' as turno,
           coalesce(x ->> 'presenca', 'turno') as presenca
      from jsonb_array_elements(v_sel) i, jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) x
     where i ->> 'op' = 'cancelar' and coalesce(i ->> 'tipo', '') <> 'reserva' and coalesce(i ->> 'motivo', '') <> 'promovida'),
  cria as (
    select (i ->> 'os')::uuid as os, x ->> 'payee_id' as payee, x ->> 'dia' as dia, x ->> 'turno' as turno,
           coalesce(x ->> 'presenca', 'turno') as presenca
      from jsonb_array_elements(v_sel) i, jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) x
     where i ->> 'op' = 'criar' and coalesce(i ->> 'tipo', '') <> 'reserva'),
  saiu as (
    select c.*, public._agenda_dia_avisado(c.payee::uuid, c.os, c.dia::date) as avisado
      from canc c
     where not exists (select 1 from cria n where n.os = c.os and n.payee = c.payee and n.dia = c.dia and n.turno = c.turno
                                              and n.presenca = c.presenca))
  select array(select distinct c.os from canc c
                where exists (select 1 from cria n where n.os = c.os)
                  and not exists (select 1 from cria n where n.os = c.os and n.dia = c.dia and n.turno = c.turno)
                order by 1),
         (select coalesce(jsonb_agg(jsonb_build_object('dia', d.dia, 'quem', d.quem) order by d.dia), '[]'::jsonb)
            from (select s.dia, case when bool_or(s.avisado = 'cliente') then 'cliente' else 'equipe' end as quem
                    from saiu s where s.avisado is not null group by s.dia) d),
         (select min(x.dia::date) from (select dia from canc union all select dia from cria) x)
    into v_os, v_dias, v_perda;

  v_nomes := array(select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                     from unnest(v_os) o join public.service_orders so on so.id = o
                     left join public.clients cl on cl.id = so.client_id
                    order by 1);
  -- o porquê: a violação com mais meios-dias entre as OS que mudam (sem elas, entre tudo o que sai); no empate, quem não vem
  select g.motivo, g.quem into v_mot, v_quem
    from (select i ->> 'motivo' as motivo, count(*) as n,
                 array_agg(distinct x ->> 'nome') filter (where x ->> 'nome' is not null) as quem
            from jsonb_array_elements(v_sel) i, jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) x
           where i ->> 'op' = 'cancelar' and coalesce((i ->> 'violada')::boolean, false)
             and (cardinality(v_os) = 0 or (i ->> 'os')::uuid = any (v_os))
           group by i ->> 'motivo') g
   order by g.n desc, g.motivo = 'pessoa' desc, g.motivo
   limit 1;
  v_ev := array(select distinct (i ->> 'os')::uuid from jsonb_array_elements(v_sel) i
                 where i ->> 'op' = 'criar' and coalesce((i ->> 'evento_real')::boolean, false) order by 1);
  return jsonb_build_object(
    'os', to_jsonb(v_os), 'os_n', coalesce(cardinality(v_os), 0), 'nomes', to_jsonb(v_nomes),
    'dias', v_dias, 'dias_n', jsonb_array_length(v_dias),
    'equipe_n', (select count(*) from jsonb_array_elements(v_dias) d where d ->> 'quem' = 'equipe'),
    'cliente_n', (select count(*) from jsonb_array_elements(v_dias) d where d ->> 'quem' = 'cliente'),
    'motivo', case v_mot
                when 'pessoa' then case when coalesce(cardinality(v_quem), 0) = 0 then 'faltou gente'
                                        when cardinality(v_quem) = 1 then v_quem[1] || ' não vem'
                                        else public._agenda_lista(v_quem, 3) || ' não vêm' end
                when 'material' then 'o material atrasou'
                when 'cliente' then 'o cliente ou o bem não está liberado'
                when 'os_saiu' then 'serviço saiu da carteira'
                when 'espera' then 'você pôs serviço em espera'
                when 'clima' then 'choveu'
              end,
    'evento_real', to_jsonb(v_ev), 'perda_em', v_perda);
end;
$function$;

comment on function public._agenda_gestor_onda_conta(jsonb) is
  'Agenda de Produção (Fase 7a, P8; spec §3.2 e §5.8): a conta da onda sobre os itens de uma proposta (só os não críticos, os que o aplicar aplicaria sem perguntar, e só das OS sem item crítico: a que já é pergunta crítica não pergunta de novo) — (a) as OS com dia mudado (compromisso vigente que sai e não volta no mesmo meio-dia, com meio-dia novo; a troca de pessoa no mesmo meio-dia, a OS nova e a reserva promovida não contam), (b) os dias já avisados mexidos (o meio-dia de compromisso que sai e não volta igual, com _agenda_dia_avisado: equipe ou cliente; o dia conta uma vez), (c) o porquê (a violação com mais meios-dias: "Roberto não vem", "o material atrasou", "o cliente ou o bem não está liberado"). {os, os_n, nomes, dias [{dia, quem}], dias_n, equipe_n, cliente_n, motivo, evento_real, perda_em}. STABLE; só o service_role.';

-- A onda (spec §3.2, §5.8 e §6.3): a proposta da vigia/gestor que mudaria o dia de mais de gestor_k_os OS de uma vez, ou mexeria
-- em mais de gestor_k_dias_avisados dias já avisados, não é aplicada: fica aberta (modo ligado) e nasce a pergunta crítica onda —
-- "Mudou muita coisa de uma vez (Roberto não vem): eu mudaria 3 serviços (Lenine, Nelson e Vanderlei) e 1 dia que a equipe já
-- sabia. Não fiz nada ainda. 1) Faço tudo como montei (recomendo; *agenda plano* mostra); 2) Mudo só o de hoje e amanhã; 3) Não
-- mudo nada: você me diz." A chave é onda:v<versão do plano>: com a agenda parada, a mesma conta não pergunta duas vezes, e a
-- pergunta fechada nessa versão (o "não mudo nada") vale até a agenda mudar (a vigia que refaz a conta não aplica). A onda aberta
-- de outra versão sai ("a agenda mudou: perguntei de novo"). Definer, sem grant: só _agenda_propor_e_aplicar a chama.
create or replace function public._agenda_gestor_onda(p_proposta uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_p      public.agenda_propostas%rowtype;
  v_c      jsonb;
  v_partes text[] := '{}';
  v_txt    text;
  v_chave  text;
  v_q      public.agenda_perguntas%rowtype;
  v_id     uuid;
  v_oss    uuid[];
begin
  if p_proposta is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_onda: sem a proposta, o dia ou a hora' using errcode = '22004';
  end if;
  select * into v_p from public.agenda_propostas where id = p_proposta;
  if not found then
    raise exception 'Não encontrei esse plano.' using errcode = 'P0002';
  end if;
  v_c := public._agenda_gestor_onda_conta(v_p.itens);
  if (v_c ->> 'os_n')::int <= cf.gestor_k_os and (v_c ->> 'dias_n')::int <= cf.gestor_k_dias_avisados then
    return jsonb_build_object('onda', false, 'conta', v_c);
  end if;

  v_chave := format('onda:v%s', v_p.versao_base);
  select q.* into v_q from public.agenda_perguntas q
   where q.chave = v_chave and q.modo = 'ligado'
   order by q.estado = 'aberta' desc, q.criada_em desc, q.id limit 1;
  if found then
    return jsonb_build_object('onda', true, 'nova', false, 'pergunta_id', v_q.id, 'estado', v_q.estado, 'conta', v_c,
      'texto', v_q.texto,
      'resumo', case when v_q.estado = 'aberta' then 'Não mudei nada: mudou muita coisa de uma vez, e eu te pergunto antes.'
                     else 'Não mudei nada: você me disse para esperar até a agenda mudar.' end);
  end if;

  if (v_c ->> 'os_n')::int > 0 then
    v_partes := v_partes || format('%s (%s)', public._agenda_plural((v_c ->> 'os_n')::int, 'serviço', 'serviços'),
                                   public._agenda_lista(array(select jsonb_array_elements_text(v_c -> 'nomes')), 4));
  end if;
  if (v_c ->> 'equipe_n')::int > 0 then
    v_partes := v_partes || format('%s que a equipe já sabia', public._agenda_plural((v_c ->> 'equipe_n')::int, 'dia', 'dias'));
  end if;
  if (v_c ->> 'cliente_n')::int > 0 then
    v_partes := v_partes || format('%s que o cliente já ouviu', public._agenda_plural((v_c ->> 'cliente_n')::int, 'dia', 'dias'));
  end if;
  v_txt := format('Mudou muita coisa de uma vez%s: eu mudaria %s. Não fiz nada ainda. 1) Faço tudo como montei (recomendo; *agenda plano* mostra); 2) Mudo só o de hoje e amanhã; 3) Não mudo nada: você me diz.',
                  coalesce(' (' || (v_c ->> 'motivo') || ')', ''), public._agenda_lista(v_partes));
  v_oss := array(select distinct x from (select (jsonb_array_elements_text(v_c -> 'os'))::uuid as x
                                          union
                                          select (i ->> 'os')::uuid from jsonb_array_elements(v_p.itens) i
                                           where i ->> 'op' = 'cancelar'
                                             and exists (select 1 from jsonb_array_elements(v_c -> 'dias') d,
                                                                       jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) a
                                                          where a ->> 'dia' = d ->> 'dia')) u
                  where x is not null order by 1);
  -- a onda aberta de outra versão do plano: a conta dela não vale mais
  update public.agenda_perguntas q
     set estado = 'resolvida', resolvida_motivo = 'a agenda mudou: perguntei de novo'
   where q.tipo = 'onda' and q.estado = 'aberta' and q.modo = 'ligado' and q.chave <> v_chave;
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao,
                                       recomendacao_texto, proposta_id, versao_base, modo, criada_em)
  values ('onda', v_chave, case when cardinality(v_oss) = 1 then v_oss[1] end, v_oss,
          greatest(coalesce((v_c ->> 'perda_em')::date, p_hoje), p_hoje), left(public._agenda_corta(v_txt, 600), 600),
          jsonb_build_array(
            jsonb_build_object('n', 1, 'texto', 'Faço tudo como montei (recomendo; *agenda plano* mostra)',
                               'efeito', jsonb_build_object('aplicar', 'tudo')),
            jsonb_build_object('n', 2, 'texto', 'Mudo só o de hoje e amanhã', 'efeito', jsonb_build_object('aplicar', 'so_evento_real')),
            jsonb_build_object('n', 3, 'texto', 'Não mudo nada: você me diz', 'efeito', jsonb_build_object('aplicar', 'nada'))),
          1, 'É o que a agenda pede com o que mudou; *agenda plano* mostra como fica', p_proposta, v_p.versao_base, 'ligado', p_agora)
  on conflict (chave, modo) where estado = 'aberta' do nothing
  returning id into v_id;
  if v_id is null then
    select q.id into v_id from public.agenda_perguntas q where q.chave = v_chave and q.modo = 'ligado' and q.estado = 'aberta';
  end if;
  return jsonb_build_object('onda', true, 'nova', true, 'pergunta_id', v_id, 'estado', 'aberta', 'conta', v_c, 'texto', v_txt,
                            'resumo', 'Não mudei nada: mudou muita coisa de uma vez, e eu te pergunto antes.');
end;
$function$;

comment on function public._agenda_gestor_onda(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P8; spec §3.2, §5.8, §6.3): a onda — com a conta de _agenda_gestor_onda_conta acima de gestor_k_os OS com dia mudado ou de gestor_k_dias_avisados dias já avisados, a pergunta crítica onda (chave onda:v<versão do plano>, modo ligado, proposta_id = a proposta que fica aberta, os_ids = as OS mexidas; "Mudou muita coisa de uma vez (Roberto não vem): eu mudaria 3 serviços (…) e 1 dia que a equipe já sabia. Não fiz nada ainda. 1) Faço tudo como montei (recomendo; *agenda plano* mostra); 2) Mudo só o de hoje e amanhã; 3) Não mudo nada: você me diz."; opções com efeito {aplicar: tudo | so_evento_real | nada}, recomendação 1). A mesma versão do plano não pergunta duas vezes (a aberta é a mesma; a fechada vale até a agenda mudar); a onda aberta de outra versão sai (resolvida). {onda, nova, pergunta_id, estado, conta, texto, resumo}; abaixo dos limites, {onda: false, conta}. Security definer, sem grant a ninguém.';

-- O encaixe na aprovação (spec §5.8; 7a-1, D7-3): passo do job do gestor a cada tique (07/22/37/52). Desligado = {pulado}. As
-- candidatas: as OS da carteira sem dia de compromisso de hoje em diante, que a vigia não acabou de tentar
-- (_agenda_vigia_ja_tentou), com algo novo desde a marca d'água (o "até" do último encaixe no mesmo modo; sem ele, um dia antes;
-- com 5 minutos de margem): a conversão em OS (converted_to_os_at: o sinal e o agrupar, que nasce aberto sem status_change), a
-- assinatura, a criação, o status_change para open/approved/scheduled em ai_lifecycle_events, o planejamento mudado, o material
-- mudado pelo dono/fornecedor/nota/Pix e os dias que o prazo vencido acabou de gravar (a ação estimar: o passo vetos do mesmo
-- tique). Ligado: _agenda_propor_e_aplicar('os', as candidatas, 'vigia') — a onda vale — e, para cada uma que ficou de fora, a
-- pergunta do gestor (_agenda_gestor_perguntas_da_os grava só quando é o que a segura). Em teste: o mesmo motor com as regras do
-- gestor ligadas só aqui dentro (agenda.gestor = 'sombra', sem gravar nada) e as perguntas secas, acrescentados ao diário do dia
-- (agenda_gestor_dia.sombra.encaixe, os 10 mais novos). A saída vai em agenda_vigia_rodadas.contagens.encaixe: {modo, de, ate,
-- candidatas, marcadas, reservadas, perguntas, onda, fora {motivo: n}, por_os [{os, numero, aprovada_em, resultado, primeiro_dia}]}
-- — a medida "da aprovação ao 1º dia marcado". Invoker, sem grant: só a rodada do gestor (definer) o chama.
create or replace function public._agenda_gestor_encaixe(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_modo   text;
  v_de     timestamptz;
  v_cand   uuid[];
  v_r      jsonb := '{}'::jsonb;
  v_p      jsonb := '{}'::jsonb;
  v_os     uuid;
  v_res    text;
  v_prim   date;
  v_mot    text;
  v_q      jsonb;
  v_it     jsonb;
  v_onda   boolean := false;
  v_por    jsonb := '[]'::jsonb;
  v_fora   jsonb := '{}'::jsonb;
  v_marc   int := 0;
  v_resv   int := 0;
  v_perg   int := 0;
  v_vencid int := 0;
  v_som    jsonb;
  v_lista  jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_encaixe: sem o dia ou a hora' using errcode = '22004';
  end if;
  v_modo := public._agenda_gestor_modo('encaixe');
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado', 'modo', v_modo);
  end if;
  -- a onda aberta de uma versão do plano que já passou não vale mais (a rodada que refizer a conta pergunta de novo)
  if v_modo = 'ligado' then
    with f as (
      update public.agenda_perguntas q
         set estado = 'resolvida', resolvida_motivo = 'a agenda mudou depois da pergunta: refaço a conta'
       where q.tipo = 'onda' and q.estado = 'aberta' and q.modo = 'ligado'
         and q.versao_base is distinct from (public._agenda_cfg()).versao_plano
      returning 1)
    select count(*)::int into v_vencid from f;
  end if;

  -- a marca d'água: o "até" do último encaixe que rodou no mesmo modo (o que a sombra viu não conta como feito de verdade)
  select max((x.contagens -> 'encaixe' ->> 'ate')::timestamptz) into v_de
    from public.agenda_vigia_rodadas x
   where x.rotina = 'gestor' and x.contagens -> 'encaixe' ->> 'modo' = v_modo
     and (x.contagens -> 'encaixe' ->> 'ate')::timestamptz <= p_agora;
  v_de := coalesce(v_de, p_agora - interval '1 day') - interval '5 minutes';

  v_cand := array(
    select k.service_order_id
      from public.os_carteira(p_hoje) k
      join public.service_orders so on so.id = k.service_order_id
     where not public._agenda_os_tem_dia(k.service_order_id, p_hoje)
       and ((so.converted_to_os_at > v_de and so.converted_to_os_at <= p_agora)
            or (so.signed_at > v_de and so.signed_at <= p_agora)
            or (so.created_at > v_de and so.created_at <= p_agora)
            or exists (select 1 from public.ai_lifecycle_events e
                        where e.entity_id = so.id and e.event_type = 'status_change'
                          and e.new_value in ('open', 'approved', 'scheduled') and e.created_at > v_de and e.created_at <= p_agora)
            or exists (select 1 from public.os_planejamento pl
                        where pl.service_order_id = so.id and pl.atualizado_em > v_de and pl.atualizado_em <= p_agora)
            or exists (select 1 from public.os_material m
                        where m.service_order_id = so.id and m.fonte in ('dono', 'fornecedor', 'nfe', 'pix')
                          and m.atualizado_em > v_de and m.atualizado_em <= p_agora)
            or exists (select 1 from public.agenda_acoes a
                        where a.service_order_id = so.id and a.tipo = 'estimar' and a.executada and a.desfeita_em is null
                          and a.criada_em > v_de and a.criada_em <= p_agora))
       and not public._agenda_vigia_ja_tentou(k.service_order_id, p_agora)
     order by k.numero, k.service_order_id);

  if cardinality(v_cand) > 0 and v_modo = 'ligado' then
    v_r := public._agenda_propor_e_aplicar('os', v_cand, 'vigia', null, p_hoje, p_agora);
    v_onda := coalesce((v_r ->> 'onda')::boolean, false);
    foreach v_os in array v_cand loop
      v_prim := (select min(a.dia) from public.agenda_alocacoes a
                  where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    and a.dia >= p_hoje and a.resultado is null);
      v_mot := null;
      if v_prim is not null then
        v_res := 'marcada';
        v_marc := v_marc + 1;
      elsif exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado in ('publicada', 'fixada')
                     and a.tipo = 'reserva' and a.dia >= p_hoje) then
        v_res := 'reservada';
        v_resv := v_resv + 1;
        v_prim := (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = v_os
                     and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje);
      elsif v_onda then
        v_res := 'onda';
      else
        v_mot := (select f ->> 'motivo' from jsonb_array_elements(coalesce(v_r -> 'fora', '[]'::jsonb)) f
                   where (f ->> 'os')::uuid = v_os limit 1);
        v_q := public._agenda_gestor_perguntas_da_os(v_os, p_hoje, p_agora, false);
        if coalesce((v_q ->> 'perguntou')::boolean, false)
           or exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'ligado' and q.critica
                       and (q.service_order_id = v_os or v_os = any (q.os_ids))) then
          v_res := 'pergunta';
          v_perg := v_perg + 1;
        else
          v_res := 'fora';
        end if;
        v_fora := v_fora || jsonb_build_object(coalesce(v_mot, 'sem_motivo'),
                                               coalesce((v_fora ->> coalesce(v_mot, 'sem_motivo'))::int, 0) + 1);
      end if;
      v_por := v_por || jsonb_build_object(
        'os', v_os, 'numero', (select so.service_order_number from public.service_orders so where so.id = v_os),
        'aprovada_em', (select coalesce(so.converted_to_os_at, so.signed_at, so.created_at) from public.service_orders so where so.id = v_os),
        'resultado', v_res, 'motivo', v_mot, 'primeiro_dia', v_prim);
    end loop;
  elsif cardinality(v_cand) > 0 then
    -- em teste: as regras do gestor valem só aqui dentro; nada é gravado (só o diário)
    perform set_config('agenda.gestor', 'sombra', true);
    begin
      v_p := public.agenda_propor('os', null, null, v_cand, '{}'::jsonb, false, 'vigia', null, p_hoje, p_agora);
      foreach v_os in array v_cand loop
        v_it := (select i from jsonb_array_elements(coalesce(v_p -> 'itens', '[]'::jsonb)) i
                  where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = v_os
                  order by i ->> 'tipo' = 'reserva', i ->> 'de' limit 1);
        v_mot := null;
        v_prim := (v_it ->> 'de')::date;
        if v_it is not null and v_it ->> 'tipo' <> 'reserva' then
          v_res := 'marcada';
          v_marc := v_marc + 1;
        elsif v_it is not null then
          v_res := 'reservada';
          v_resv := v_resv + 1;
        else
          v_mot := (select f ->> 'motivo' from jsonb_array_elements(coalesce(v_p -> 'fora', '[]'::jsonb)) f
                     where (f ->> 'os')::uuid = v_os limit 1);
          v_q := public._agenda_gestor_perguntas_da_os(v_os, p_hoje, p_agora, true);
          if v_q ? 'chave' then
            v_res := 'pergunta';
            v_perg := v_perg + 1;
          else
            v_res := 'fora';
          end if;
          v_fora := v_fora || jsonb_build_object(coalesce(v_mot, 'sem_motivo'),
                                                 coalesce((v_fora ->> coalesce(v_mot, 'sem_motivo'))::int, 0) + 1);
        end if;
        v_por := v_por || jsonb_build_object(
          'os', v_os, 'numero', (select so.service_order_number from public.service_orders so where so.id = v_os),
          'aprovada_em', (select coalesce(so.converted_to_os_at, so.signed_at, so.created_at) from public.service_orders so where so.id = v_os),
          'resultado', v_res, 'motivo', v_mot, 'primeiro_dia', v_prim,
          'texto', case when v_res = 'pergunta' then v_q ->> 'texto' else v_it ->> 'texto' end);
      end loop;
    exception when others then
      perform set_config('agenda.gestor', '', true);
      raise;
    end;
    perform set_config('agenda.gestor', '', true);
    select g.sombra into v_som from public.agenda_gestor_dia g where g.dia = p_hoje;
    v_lista := coalesce(v_som -> 'encaixe', '[]'::jsonb)
               || jsonb_build_array(jsonb_build_object('calculado_em', p_agora, 'de', v_de, 'por_os', v_por));
    v_lista := (select coalesce(jsonb_agg(e order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_lista) with ordinality t(e, o)
                 where o > jsonb_array_length(v_lista) - 10);
    perform public._agenda_gestor_dia_gravar(p_hoje, 'sombra', coalesce(v_som, '{}'::jsonb) || jsonb_build_object('encaixe', v_lista),
                                             p_agora);
  end if;

  return jsonb_build_object('modo', v_modo, 'simulacao', v_modo <> 'ligado', 'de', v_de, 'ate', p_agora,
                            'candidatas', coalesce(cardinality(v_cand), 0), 'marcadas', v_marc, 'reservadas', v_resv,
                            'perguntas', v_perg, 'onda', v_onda, 'onda_pergunta', v_r -> 'pergunta_id',
                            'ondas_vencidas', v_vencid, 'proposta_id', v_r -> 'proposta_id', 'fora', v_fora, 'por_os', v_por);
end;
$function$;

comment on function public._agenda_gestor_encaixe(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P8; spec §5.8, D7-3): o encaixe na aprovação, passo de todo tique do job agenda-gestor. Desligado (_agenda_gestor_modo(''encaixe'')) = {pulado}. Candidatas: as OS da carteira sem dia de compromisso de hoje em diante (_agenda_os_tem_dia), não tentadas pela vigia (_agenda_vigia_ja_tentou), com algo novo desde a marca d''água (o "até" do último encaixe no mesmo modo, em agenda_vigia_rodadas.contagens.encaixe; sem ele, p_agora − 1 dia; margem de 5 min): converted_to_os_at (o sinal; o agrupar, sem status_change), signed_at, created_at, status_change para open/approved/scheduled (ai_lifecycle_events), os_planejamento.atualizado_em, os_material.atualizado_em com fonte dono/fornecedor/nfe/pix, e a ação estimar (os dias do prazo vencido do passo vetos do mesmo tique). Ligado: _agenda_propor_e_aplicar(''os'', candidatas, ''vigia'') (a onda vale) e a pergunta do gestor das que ficaram de fora (_agenda_gestor_perguntas_da_os); a onda aberta de versão do plano que já passou é resolvida. Em teste: agenda.gestor = ''sombra'' só dentro do passo, agenda_propor sem gravar e as perguntas secas, acrescentados a agenda_gestor_dia.sombra.encaixe (os 10 mais novos). {modo, simulacao, de, ate, candidatas, marcadas, reservadas, perguntas, onda, onda_pergunta, ondas_vencidas, proposta_id, fora {motivo: n}, por_os [{os, numero, aprovada_em, resultado (marcada | reservada | onda | pergunta | fora), motivo, primeiro_dia}]}. Invoker, sem grant: só a rodada do gestor o chama.';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7:") ──────────────────────────
-- Fora dos blocos nenhuma linha muda (o E6 de supabase/tests/agenda_fase7a_encaixe.sql confere). Quem recriar de novo qualquer
-- uma delas copia DESTA migration (fase7-registro.md §2: agenda_propor no 7b P4; _agenda_gestor_decidir no 7a P9;
-- _agenda_criticidade, _agenda_criticidade_da_acao e _agenda_propor_e_aplicar, quem vier).

-- _agenda_criticidade (de 20261025100200_agenda_fase2_motor.sql)
create or replace function public._agenda_criticidade(p_os uuid, p_fim_antes date, p_inicio_antes date, p_fim_depois date,
                                                      p_inicio_depois date, p_hoje date,
                                                      p_cancela uuid[] default '{}'::uuid[], p_violadas uuid[] default '{}'::uuid[])
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_precisa date;
  v_conf    date;
  -- FASE 7: (7a P8) a zona travada do gestor: o prometido da OS e o dia já dito que sairia
  v_f7_pl   public.os_planejamento%rowtype;
  v_f7_dia  text;
  -- FASE 7: fim
begin
  select pl.precisa_ate into v_precisa from public.os_planejamento pl where pl.service_order_id = p_os;
  -- FASE 7: (7a P8, spec §3.2 e §5.8) a zona travada do gestor (a regra zona_travada). 0. O fim prometido FIRME ao cliente
  -- (os_planejamento.prometido_tipo firme, prometido_ate) deixaria de ser cumprido, e o fim publicado de antes o cumpria:
  -- dia_prometido — antes do nao_cabe, que é o precisa_ate dito pelo dono. Só para quem já tinha plano (p_fim_antes).
  if public._agenda_gestor_regra('zona_travada') then
    select pl.* into v_f7_pl from public.os_planejamento pl where pl.service_order_id = p_os;
    if v_f7_pl.prometido_tipo = 'firme' and v_f7_pl.prometido_ate is not null and p_fim_antes is not null
       and p_fim_antes <= v_f7_pl.prometido_ate and p_fim_depois > v_f7_pl.prometido_ate then
      return 'dia_prometido';
    end if;
  end if;
  -- FASE 7: fim
  -- 1. A data que o cliente precisa (dita pelo dono) deixaria de ser cumprida.
  if v_precisa is not null and p_fim_depois > v_precisa and (p_fim_antes is null or p_fim_antes <= v_precisa) then
    return 'nao_cabe';
  end if;
  -- 2. O fim publicado anda.
  if p_fim_antes is not null and p_fim_depois > p_fim_antes then
    if p_fim_depois - p_fim_antes >= cf.atraso_longo_dias then
      return 'atraso_longo';
    end if;
    if exists (select 1 from public.agenda_acoes a
                where a.service_order_id = p_os and a.executada and a.desfeita_em is null and coalesce(a.atraso_du, 0) > 0) then
      return 'segundo_atraso';
    end if;
    select (so.client_confirmed_for at time zone 'America/Sao_Paulo')::date into v_conf
      from public.service_orders so where so.id = p_os;
    if p_inicio_antes is not null and p_inicio_depois is not null and v_conf = p_inicio_antes
       and public.agenda_du_entre(p_inicio_antes, p_inicio_depois) > cf.remarcar_confirmado_du then
      return 'remarcar_confirmado';
    end if;
  end if;
  -- 3. Sairia um meio-dia que o dono fixou, sem que ele tenha ficado impossível.
  if exists (select 1 from public.agenda_alocacoes a
              where a.id = any (coalesce(p_cancela, '{}'::uuid[])) and a.estado = 'fixada' and a.fixado_por = 'dono'
                and not (a.id = any (coalesce(p_violadas, '{}'::uuid[])))) then
    return 'fixada_pelo_dono';
  end if;
  -- FASE 7: (7a P8, spec §3.2 e §5.8) 4. A zona travada: sairia (p_cancela) um meio-dia de compromisso de um dia que já foi dito
  -- — ao cliente (_agenda_dia_avisado = cliente: ele ouviu o dia, ou o prometido firme o cobre) → dia_prometido; à equipe (a
  -- ficha ou a confirmação ligada daquela pessoa naquele dia já saiu) → dia_avisado —, sem que ele tenha ficado impossível
  -- (p_violadas: com a regra, agenda_propor passa _agenda_zona_fora — a violação, o resto do meio-dia dela e o que volta igual
  -- no encaixe novo). O cliente vence a equipe. A reserva nunca foi dita a ninguém: não conta.
  if public._agenda_gestor_regra('zona_travada') then
    select case when bool_or(x.d = 'cliente') then 'dia_prometido' when bool_or(x.d = 'equipe') then 'dia_avisado' end
      into v_f7_dia
      from (select public._agenda_dia_avisado(a.payee_id, a.service_order_id, a.dia) as d
              from public.agenda_alocacoes a
             where a.id = any (coalesce(p_cancela, '{}'::uuid[])) and not (a.id = any (coalesce(p_violadas, '{}'::uuid[])))
               and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')) x;
    if v_f7_dia is not null then
      return v_f7_dia;
    end if;
  end if;
  -- FASE 7: fim
  return null;
end;
$function$;

comment on function public._agenda_criticidade(uuid, date, date, date, date, date, uuid[], uuid[]) is
  'Agenda de Produção (Fase 2, P2): a regra única do que é crítico (pergunta antes), na ordem — nao_cabe (precisa_ate dito pelo dono e o fim novo passa dela, sem que o fim de antes já passasse); com o fim publicado andando: atraso_longo (atraso_longo_dias corridos ou mais), segundo_atraso (a OS já teve atraso executado e não desfeito), remarcar_confirmado (o cliente confirmou o 1º dia e o novo início passa de remarcar_confirmado_du dias úteis); fixada_pelo_dono (p_cancela tem meio-dia fixado pelo dono fora de p_violadas). null = o gestor faz sozinho. A mesma regra que agenda_saude reconfere. FASE 7 (7a P8, spec §3.2 e §5.8): com a regra zona_travada do gestor (_agenda_gestor_regra), a zona travada — (0) antes do nao_cabe, o fim que passaria do prometido firme ao cliente (os_planejamento.prometido_tipo firme e prometido_ate), que o fim publicado de antes cumpria: dia_prometido; (4) depois de fixada_pelo_dono, o meio-dia de compromisso de p_cancela fora de p_violadas cujo dia já foi dito (_agenda_dia_avisado): ao cliente → dia_prometido, à equipe → dia_avisado (o cliente vence; reserva não conta). Com a regra, agenda_propor passa em p_violadas o que não conta para a zona (_agenda_zona_fora: a violação, o resto do meio-dia dela e o que volta igual no encaixe novo; nunca o fixado pelo dono). Sem a regra, a de antes, byte a byte.';

-- _agenda_criticidade_da_acao (de 20261025100300_agenda_fase2_conferencia_vigia.sql)
create or replace function public._agenda_criticidade_da_acao(p_acao uuid)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf        public.agenda_config := public._agenda_cfg();
  a         public.agenda_acoes%rowtype;
  v_fim_a   date;
  v_fim_d   date;
  v_ini_a   date;
  v_ini_d   date;
  v_precisa date;
  v_conf    date;
  -- FASE 7: (7a P8) a zona travada sobre a ação: o prometido da OS e o dia já dito que saiu
  v_f7_pl   public.os_planejamento%rowtype;
  v_f7_dia  text;
  -- FASE 7: fim
begin
  select * into a from public.agenda_acoes where id = p_acao;
  if not found or a.service_order_id is null then
    return null;
  end if;
  v_fim_a := (a.antes ->> 'fim')::date;
  v_fim_d := (a.depois ->> 'fim')::date;
  v_ini_a := (select min((x ->> 'dia')::date) from jsonb_array_elements(coalesce(a.antes -> 'alocacoes', '[]'::jsonb)) x);
  v_ini_d := (select min((x ->> 'dia')::date) from jsonb_array_elements(coalesce(a.depois -> 'alocacoes', '[]'::jsonb)) x);
  select pl.precisa_ate into v_precisa from public.os_planejamento pl where pl.service_order_id = a.service_order_id;
  -- 1. a data que o cliente precisa
  if v_precisa is not null and v_fim_d > v_precisa and (v_fim_a is null or v_fim_a <= v_precisa) then
    return 'nao_cabe';
  end if;
  -- 2. o fim publicado andou
  if v_fim_a is not null and v_fim_d > v_fim_a then
    if v_fim_d - v_fim_a >= cf.atraso_longo_dias then
      return 'atraso_longo';
    end if;
    if exists (select 1 from public.agenda_acoes b
                where b.service_order_id = a.service_order_id and b.id <> a.id and b.executada and coalesce(b.atraso_du, 0) > 0
                  and b.criada_em < a.criada_em and (b.desfeita_em is null or b.desfeita_em > a.criada_em)) then
      return 'segundo_atraso';
    end if;
    select (so.client_confirmed_for at time zone 'America/Sao_Paulo')::date into v_conf
      from public.service_orders so where so.id = a.service_order_id;
    if v_ini_a is not null and v_ini_d is not null and v_conf = v_ini_a
       and public.agenda_du_entre(v_ini_a, v_ini_d) > cf.remarcar_confirmado_du then
      return 'remarcar_confirmado';
    end if;
  end if;
  -- 3. saiu um meio-dia fixado pelo dono sem ter ficado impossível (a pessoa, a OS ou a espera que ele mesmo pôs)
  if exists (select 1 from public.agenda_alocacoes x
              where x.id = any (a.alocacoes_canceladas) and x.fixado_por = 'dono'
                and x.cancelada_motivo is distinct from 'pessoa' and x.cancelada_motivo is distinct from 'os_saiu'
                and x.cancelada_motivo is distinct from 'espera') then
    return 'fixada_pelo_dono';
  end if;
  -- FASE 7: (7a P8, spec §5.8) a mesma zona travada de _agenda_criticidade, sobre a ação executada que marcou meios-dias
  -- (alocacoes_criadas) — contada só a partir do OK de ligar o gestor (marcar_sozinho_desde: antes, a regra não valia). (0) O
  -- fim passou do prometido firme ao cliente, que o fim de antes cumpria → dia_prometido. (4) Saiu, sem ter ficado impossível
  -- (cancelada como "replanejado": não a violação; nem no meio-dia de uma cancelada pela violação; nem de volta igual nas
  -- criadas), um meio-dia de compromisso de um dia dito ANTES da ação — ao cliente (_agenda_cliente_ouviu até a ação, ou o
  -- prometido firme o cobre) → dia_prometido; à equipe (a ficha ou a confirmação ligada criada antes da ação) → dia_avisado.
  if public._agenda_gestor_regra('zona_travada') and cf.marcar_sozinho_desde is not null
     and a.criada_em >= cf.marcar_sozinho_desde and cardinality(a.alocacoes_criadas) > 0 then
    select pl.* into v_f7_pl from public.os_planejamento pl where pl.service_order_id = a.service_order_id;
    if v_f7_pl.prometido_tipo = 'firme' and v_f7_pl.prometido_ate is not null and v_fim_a is not null
       and v_fim_a <= v_f7_pl.prometido_ate and v_fim_d > v_f7_pl.prometido_ate then
      return 'dia_prometido';
    end if;
    select case when bool_or(y.d = 'cliente') then 'dia_prometido' when bool_or(y.d = 'equipe') then 'dia_avisado' end
      into v_f7_dia
      from (select case
                     when public._agenda_cliente_ouviu(x.service_order_id, x.dia, a.criada_em)
                          or (v_f7_pl.prometido_tipo = 'firme'
                              and x.dia between coalesce(v_f7_pl.prometido_de, v_f7_pl.prometido_ate) and v_f7_pl.prometido_ate)
                       then 'cliente'
                     when exists (select 1 from public.agenda_equipe_mensagens m
                                   where m.payee_id = x.payee_id and m.dia = x.dia and m.tipo in ('ficha', 'confirmar')
                                     and m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
                                     and m.criada_em <= a.criada_em)
                       then 'equipe'
                   end as d
              from public.agenda_alocacoes x
             where x.id = any (a.alocacoes_canceladas) and x.tipo <> 'reserva' and x.cancelada_motivo = 'replanejado'
               and not exists (select 1 from public.agenda_alocacoes v
                                where v.id = any (a.alocacoes_canceladas) and v.id <> x.id and v.dia = x.dia and v.turno = x.turno
                                  and v.cancelada_motivo in ('pessoa', 'material', 'cliente', 'os_saiu', 'espera'))
               and not exists (select 1 from public.agenda_alocacoes n
                                where n.id = any (a.alocacoes_criadas) and n.payee_id = x.payee_id and n.dia = x.dia
                                  and n.turno = x.turno and n.presenca = x.presenca)) y;
    if v_f7_dia is not null then
      return v_f7_dia;
    end if;
  end if;
  -- FASE 7: fim
  return null;
end;
$function$;

comment on function public._agenda_criticidade_da_acao(uuid) is
  'Agenda de Produção (Fase 2, P3): a regra única do que é crítico (_agenda_criticidade) reconferida sobre uma ação executada — nao_cabe, atraso_longo, segundo_atraso (só pelas ações da OS anteriores a esta e não desfeitas até ela), remarcar_confirmado, fixada_pelo_dono (meio-dia fixado pelo dono cancelado sem a pessoa ou a OS ter saído). Para a agenda_saude. FASE 7 (7a P8, spec §5.8): com a regra zona_travada, na ação executada que marcou meios-dias (alocacoes_criadas) e foi feita a partir do OK de ligar o gestor (marcar_sozinho_desde), a mesma zona travada — o fim que passou do prometido firme ao cliente (dia_prometido) e o meio-dia cancelado como replanejado (não a violação, nem no meio-dia de uma violação, nem de volta igual nas criadas) de um dia dito ANTES da ação: ao cliente (_agenda_cliente_ouviu até a ação, ou o prometido firme) → dia_prometido; à equipe (ficha ou confirmação ligada criada antes) → dia_avisado. A saúde conta (zona_travada_mexida, dia_avisado_sem_pergunta). Sem a regra, a de antes, byte a byte.';

-- agenda_propor (de 20261031100200_agenda_fase7a_prontidao.sql)
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
  'Agenda de Produção (Fase 2, P2): o motor — guloso serial determinístico (mesma entrada, mesma saída). Escopo semana (publica os blocos que COMEÇAM de segunda a sábado da semana seguinte), os ou replano (as OS de p_os, depois do congelado, no horizonte). Etapas: estabilidade (_agenda_violacoes: só sai o que não pode mais acontecer; o publicado não violado nunca vira "mover"), a fila por classe (_agenda_classe_da_os) na ordem (classe, prioridade do dono, razão crítica, sinal pago, aprovação, número), o encaixe (_agenda_encaixar: congelamento hoje + o próximo dia útil, salvo evento real e pedido do dono; ≤ wip_max frentes; o dono como tambor; teto de carga_max por pessoa e semana; multi-dia com no máximo interrupcoes_max dias parados), a sobrecarga (a OS com data dita que não cabe vira a pergunta crítica nao_cabe, com as opções simuladas e a recomendação; o banco nunca escolhe), o atraso crítico de quem já tinha plano (_agenda_criticidade), as reservas (teto, condicionada com a data-limite, pátio), a validação (_agenda_validar_itens: inválida nunca sai), o diff (itens), as OS de fora com quem trava, a carga, a pontuação e os textos. Restrições: {fixar:[{os, de, ate, pessoa}], tirar:[os], so_depois_de:[{os, dia}], atrasar:[os], aceitar_atraso:[os], acima_da_carga, decisao}. Com p_persistir: agenda_propostas (modo = modo_proposta; a aberta anterior fica obsoleta), as alocações em estado proposta e as perguntas críticas. Sem persistir, o texto termina com "É simulação: não muda nada.". Só service_role. CORREÇÃO FASE 6 (C1, item 14): a reserva por teto da OS que precisa do dono, com a capacidade dele em uso abaixo de carga_max, diz "não coube na sua parte da semana (56%)" (a carga de _agenda_carga_da_pessoa), e não "na carga de 80%". CORREÇÃO 29/10 (P3): (a) a entrada da fila da OS com reserva vigente (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira compromisso" cancela) leva res_propria (a pessoa × semana de cada meio-dia reservado), e o encaixe do compromisso dela não conta a própria reserva no lugar até 100% — a promoção da reserva cabe com o teto apertado (o João, 4 de 4 na semana); a reserva das outras OS continua contando. (b) Com a agenda automática ligada e reserva no que entra, o resumo separa o marcado firme do reservado e diz quem ("Semana de 03 a 06/11 (seg 02 é Finados): 1 reservado (Lenine), nada marcado firme, 10 de fora."), e o título da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme", que abre o "Publiquei a semana de …"); sem reserva, ou fora de ligado, os de antes. FASE 7 (7a P3): o item de compromisso com a fonte orcamento (a estimativa do orçamento como dias firmes, só com a regra estimativa) termina "(estimativa minha: 6 dias)."; a recomendação das críticas dia_avisado ("A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia") e dia_prometido ("É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje"), que só nascem com a zona travada do P8. FASE 7 (7a P8, spec §3.2 e §5.8): com a regra zona_travada, a criticidade de cada compromisso colocado é refeita com p_violadas = _agenda_zona_fora (o que não conta para o dia já avisado: a violação, o resto do meio-dia dela e o que volta igual neste encaixe; nunca o fixado pelo dono): o meio-dia de um dia já dito à equipe ou ao cliente que sairia sem ter ficado impossível, e o fim que passaria do prometido firme, viram as críticas dia_avisado e dia_prometido, com a pergunta e a recomendação de sempre. Sem a regra, a de antes, byte a byte.';

-- _agenda_propor_e_aplicar (de 20261025100300_agenda_fase2_conferencia_vigia.sql)
create or replace function public._agenda_propor_e_aplicar(p_escopo text, p_os uuid[], p_origem text, p_autor uuid,
                                                           p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_por  text;
  v_p    jsonb;
  v_a    jsonb;
  v_ids  uuid[];
  -- FASE 7: (7a P8) a onda
  v_f7_onda jsonb;
  -- FASE 7: fim
begin
  if p_origem is null or p_origem not in ('motor', 'vigia', 'conferencia', 'dono') then
    raise exception 'Origem desconhecida para replanejar: "%".', coalesce(p_origem, '') using errcode = '22023';
  end if;
  if cf.modo_proposta = 'desligado' then
    return jsonb_build_object('ok', false, 'modo', 'desligado', 'texto', 'A agenda automática está desligada: não mudo nada.');
  end if;
  -- quem "criou" a proposta: a conferência é o dono dizendo o que aconteceu
  v_por := case p_origem when 'conferencia' then 'dono' when 'dono' then 'dono' when 'vigia' then 'vigia' else 'motor' end;
  v_p := public.agenda_propor(p_escopo, null, null, p_os, '{}'::jsonb, true, v_por, p_autor, p_hoje, p_agora);
  if not coalesce((v_p ->> 'ok')::boolean, false) then
    return v_p || jsonb_build_object('modo', cf.modo_proposta);
  end if;
  if cf.modo_proposta = 'ligado' then
    -- FASE 7: (7a P8, spec §3.2 e §5.8) a onda: numa rodada da vigia ou do gestor (origem vigia), com a regra onda, a proposta que
    -- mudaria o dia de mais de gestor_k_os OS de uma vez, ou mexeria em mais de gestor_k_dias_avisados dias já avisados, não é
    -- aplicada: fica aberta (modo ligado) e nasce a pergunta crítica onda (_agenda_gestor_onda). A reserva promovida, a OS nova e a
    -- troca de pessoa no mesmo meio-dia não contam.
    if p_origem = 'vigia' and public._agenda_gestor_regra('onda') then
      v_f7_onda := public._agenda_gestor_onda((v_p ->> 'proposta_id')::uuid, p_hoje, p_agora);
      if coalesce((v_f7_onda ->> 'onda')::boolean, false) then
        return jsonb_build_object('ok', false, 'onda', true, 'modo', 'ligado', 'simulacao', false,
                                  'proposta_id', v_p ->> 'proposta_id', 'pergunta_id', v_f7_onda -> 'pergunta_id',
                                  'texto', v_f7_onda ->> 'resumo', 'acoes', '[]'::jsonb, 'publicadas', 0, 'canceladas', 0,
                                  'perguntas', coalesce(v_p -> 'perguntas', '[]'::jsonb)
                                               || case when v_f7_onda ->> 'estado' = 'aberta'
                                                       then jsonb_build_array(jsonb_build_object(
                                                              'tipo', 'onda', 'chave', format('onda:v%s', v_p ->> 'versao_base'),
                                                              'texto', v_f7_onda ->> 'texto'))
                                                       else '[]'::jsonb end,
                                  'fora', coalesce(v_p -> 'fora', '[]'::jsonb), 'conta_onda', v_f7_onda -> 'conta');
      end if;
    end if;
    -- FASE 7: fim
    v_a := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, p_origem, p_autor, null, p_hoje, p_agora);
    if not coalesce((v_a ->> 'ok')::boolean, false) then
      -- a proposta recém-calculada não aplicou: nunca deveria acontecer (o motor valida antes de sair). Fica consultável.
      perform public.log_app_error('db', 'agenda: a proposta da ' || p_origem || ' não aplicou: ' || coalesce(v_a ->> 'texto', '?'),
                                   'agenda', p_origem || ':aplicar', 'warn',
                                   jsonb_build_object('proposta', v_p ->> 'proposta_id', 'violacoes', v_a -> 'violacoes',
                                                      'p_hoje', p_hoje, 'p_agora', p_agora));
    end if;
    return jsonb_build_object('ok', coalesce((v_a ->> 'ok')::boolean, false), 'modo', 'ligado', 'simulacao', false,
                              'proposta_id', v_p ->> 'proposta_id', 'texto', v_a ->> 'texto',
                              'acoes', coalesce(v_a -> 'acoes', '[]'::jsonb),
                              'publicadas', coalesce((v_a ->> 'publicadas')::int, 0), 'canceladas', coalesce((v_a ->> 'canceladas')::int, 0),
                              'perguntas', coalesce(v_p -> 'perguntas', '[]'::jsonb), 'fora', coalesce(v_p -> 'fora', '[]'::jsonb));
  end if;
  v_ids := public._agenda_acoes_da_sombra((v_p ->> 'proposta_id')::uuid, p_origem, p_autor, p_hoje, p_agora);
  return jsonb_build_object('ok', true, 'modo', cf.modo_proposta, 'simulacao', true, 'proposta_id', v_p ->> 'proposta_id',
                            'texto', case when cardinality(v_ids) = 0 then 'Em teste (nada foi mudado): eu não mudaria nada.'
                                          else 'Em teste (nada foi mudado): eu teria feito assim — '
                                               || (select string_agg(a.texto, ' ' order by a.criada_em, a.id)
                                                     from public.agenda_acoes a where a.id = any (v_ids)) end,
                            'acoes', to_jsonb(v_ids), 'publicadas', 0, 'canceladas', 0,
                            'perguntas', coalesce(v_p -> 'perguntas', '[]'::jsonb), 'fora', coalesce(v_p -> 'fora', '[]'::jsonb));
end;
$function$;

comment on function public._agenda_propor_e_aplicar(text, uuid[], text, uuid, date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): agenda_propor(persistir) + — em ligado — agenda_aplicar dos itens não críticos (o que não aplicou vai para app_error_logs, warn) ou — em sombra — _agenda_acoes_da_sombra (executada = false). Origens: motor, vigia, conferencia (a proposta fica criada_por dono), dono. {ok, modo, simulacao, proposta_id, texto, acoes, publicadas, canceladas, perguntas, fora}. FASE 7 (7a P8, spec §3.2 e §5.8): em ligado, na origem vigia (a vigia e o gestor) e com a regra onda, antes de aplicar: _agenda_gestor_onda — mais de gestor_k_os OS com dia mudado ou mais de gestor_k_dias_avisados dias já avisados mexidos (a reserva promovida, a OS nova e a troca de pessoa no mesmo meio-dia não contam) = nada aplicado, a proposta fica aberta e a pergunta crítica onda nasce (uma por versão do plano); devolve {ok: false, onda: true, proposta_id, pergunta_id, texto "Não mudei nada: mudou muita coisa de uma vez, e eu te pergunto antes.", perguntas (com a da onda), fora, conta_onda}. Sem a regra, a de antes, byte a byte.';

-- _agenda_gestor_decidir (de 20261031100300_agenda_fase7a_perguntas.sql)
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
  'Agenda de Produção (Fase 7a, P4): o despacho das perguntas do gestor (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal), chamado por agenda_decidir (o dono) e por _agenda_gestor_vetos (p_via prazo). Só situacao e estimativa decidem aqui (os outros tipos: "não tem opções" ou "ainda não sei decidir", até os pacotes P8, P9, P11 e P12 recriarem ESTA função). Opção com efeito dias: se a pergunta que o gestor faria agora para a OS ainda é esta, grava os dias (_agenda_gestor_gravar_dias; a pergunta respondida pelo dono, ou resolvida "sem resposta até sex 30/10 18:00: ficou como eu disse"); senão resolve a pergunta e nada muda. dizer: fica aberta com a escolha (o prazo não vale mais), "Me diga os dias (ex.: ''Nelson 3 dias'')."; terminou: "Use *concluiu Nelson*."; nao_fazer: "não marco". Só com a pergunta e o modo de quem a fez ligados. Trava agenda_plano. {ok, gestor true, texto, acao_id?, aberta?, sem_condicao?}. Security definer, sem grant a ninguém. FASE 7 (7a P8, spec §5.8): a onda — com a agenda na mesma versão do plano da pergunta, a conta é refeita pelo motor com os parâmetros da proposta dela (agenda_propor persistido, criada_por dono) e aplicada com a pergunta (ações críticas): 1 tudo ("Feito: …"); 2 só as OS de evento real, o de hoje e amanhã (sem nenhuma: "Não havia nada de hoje e amanhã para mudar: não mudei nada."); 3 nada (a proposta descartada; "Combinado: não mudei nada. …"). Com a agenda mudada desde a pergunta, a pergunta resolve e nada muda ("A agenda mudou desde a pergunta: …"). Falhou = nada fica, a pergunta continua aberta. Sem prazo (via prazo: "Essa pergunta não tem prazo"). O P9 e o P12 recriam esta função copiando DESTA migration.';

-- ── 3. Portas ──────────────────────────────────────────────────────────────────────────────────────────────────
-- As peças do motor (a conta da zona e a da onda) são internas: só o service_role (o motor, que é dele, as chama). A pergunta da
-- onda escreve (definer): sem grant a ninguém, nem service_role (só _agenda_propor_e_aplicar a chama). O passo do encaixe é
-- invoker e sem grant, como os outros passos do gestor (a rodada, definer, o chama).
revoke all on function public._agenda_zona_fora(jsonb, uuid, jsonb), public._agenda_gestor_onda_conta(jsonb)
  from public, anon, authenticated;
grant execute on function public._agenda_zona_fora(jsonb, uuid, jsonb), public._agenda_gestor_onda_conta(jsonb) to service_role;
revoke all on function public._agenda_gestor_onda(uuid, date, timestamptz), public._agenda_gestor_encaixe(date, timestamptz)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function public._agenda_criticidade(uuid, date, date, date, date, date, uuid[], uuid[]),
  public._agenda_criticidade_da_acao(uuid)
  from public, anon;
grant execute on function public._agenda_criticidade(uuid, date, date, date, date, date, uuid[], uuid[]),
  public._agenda_criticidade_da_acao(uuid)
  to authenticated, service_role;
revoke all on function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  from public, anon, authenticated;
grant execute on function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  to service_role;
revoke all on function public._agenda_propor_e_aplicar(text, uuid[], text, uuid, date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)
  from public, anon, authenticated, service_role;
