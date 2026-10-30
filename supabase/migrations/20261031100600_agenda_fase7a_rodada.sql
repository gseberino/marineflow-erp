-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P7: a rodada do gestor da agenda — o job agenda-gestor,
-- o "eu marcaria assim" (a sombra), as perguntas antes de marcar, a linha do gestor no fechamento das 17:30 e as vagas da agenda
-- nele, o foco *agenda gestor*, a palavra *gestor, só propor* e o *desfaz* das ações do gestor.
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R, §3.1 itens 2, 3, 12 e 13, §3.2, §5.7, §6.1, §6.2, §6.4, §7, §8.4 R1–R9,
-- §11); nomes: fase7-registro.md §1 (agenda_gestor_rodar e os passos, o job agenda-gestor, _agenda_gestor_perguntas,
-- _agenda_gestor_sombra, _agenda_ver_gestor, agenda_gestor_dito) e §2 (a cadeia de agenda_desfazer — o 7b P3 copia DESTA —,
-- agenda_saude — o 7b P5 copia DESTA — e agenda_ver — o 7c P6 copia DESTA). Depende da 20261031100000 (P1: os modos, o portão,
-- o diário), da 20261031100100 (P2: a estimativa e a dupla), da 20261031100200 (P3: a prontidão e o motor) e da 20261031100300
-- (P4: as perguntas, o prazo e a chamada da equipe).
--
-- ═══ FUNÇÕES + CRON — OK NOMEADO ═══ (12 funções novas — 5 do gestor e 7 ajudantes de texto —, 6 recriadas, 1 job do pg_cron; nenhuma tabela, coluna,
-- lista ou dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7a/p7/montar-migration.mjs: as recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote e nas 20261031* do P1 ao
-- P6): _agenda_linhas_do_fechamento de 20261030100500 (a revisão do lote), agenda_textos_do_fechamento de 20261025100500,
-- agenda_ver de 20261030100100 (o P2 do lote), agenda_desfazer de 20261029100600, _agenda_ver_plano de 20261030100000 (o P1 do
-- lote) e agenda_saude de 20261029100950. As mudanças estão só nos blocos "-- FASE 7: … -- FASE 7: fim"; fora deles nenhuma linha
-- muda (o R9 de supabase/tests/agenda_fase7a_rodada.sql confere).
--
-- POR QUE: os pacotes P1 a P6 deram ao motor as regras do gestor (a estimativa do orçamento como dias firmes, 1 pessoa, a peça
-- barata que não segura a data, o prazo padrão da peça sem fornecedor, o teto da equipe-semana, as perguntas com prazo, a medição
-- contra a estimativa), mas ninguém as roda: o portão só abre com o modo ligado, e em sombra ninguém faz a conta do "eu marcaria
-- assim". Este pacote é o gestor trabalhando: um job próprio (fora da vigia, que está perto do limite de 8 s) que roda os passos
-- do gestor a cada 15 min e, no fim da tarde, os do dia; a sombra que mostra ao dono, no fechamento e no foco, o que o gestor
-- faria; a palavra que o faz só sugerir na hora; e o *desfaz* das ações novas dele.
--
-- O QUE MUDA:
--   1. agenda_gestor_rodar (o job agenda-gestor: '7,22,37,52 10-23 * * 1-6' = 07:07 a 20:52 de Brasília, seg a sáb, com o
--      statement_timeout de gestor_tempo_max): os passos _agenda_gestor_<passo>(date, timestamptz) de todo tique (vetos,
--      encaixe, bem, sinal, puxar) e, no 1º tique de dia útil a partir de gestor_hora_revisao (16:45; o 1º é o das 16:52), os
--      diários (perguntas, compre_ate, revisao, fichas, orcamentos, sabado, equipe, sombra). O passo cuja função ainda não existe
--      é pulado: aqui rodam vetos (P4), perguntas, equipe (P4) e sombra; encaixe (P8), revisao (P9), compre_ate (P10), fichas
--      (P11), sinal, orcamentos e sabado (P12), bem (P13) e puxar (7e) só entram quando o pacote deles criar a função. Erro de um
--      passo → app_error_logs (gestor:<passo>) e segue; o tempo estourado (query_canceled) registra, grava a rodada e encerra.
--      Uma linha em agenda_vigia_rodadas (rotina gestor) por rodada. Com marcar, encaixe, revisao e compre_ate desligados, nada.
--   2. _agenda_gestor_sombra (diário, só com marcar, encaixe ou revisao em sombra): o MESMO motor com as regras ligadas só dentro
--      dela (agenda.gestor = 'sombra'; agenda_propor persistir false) sobre a carteira sem compromisso, e as perguntas secas;
--      grava agenda_gestor_dia.sombra e texto_sombra ("Agenda em teste (nada mudou): eu marcaria assim — …").
--   3. _agenda_gestor_perguntas (diário, só com marcar ligado de verdade): grava a pergunta situacao/estimativa, com o prazo.
--   4. _agenda_linhas_do_fechamento: a linha gestor (o texto_sombra de hoje, com marcar em sombra), a linha compras (o diário de
--      hoje, que o P10 grava; inerte até lá) e a pergunta em que o dono escolheu "eu digo os dias" não volta.
--      agenda_textos_do_fechamento: vagas_garantidas e vaga_teria (com modo_vaga_fechamento fora de desligado).
--   5. agenda_ver: o foco gestor (_agenda_ver_gestor). _agenda_ver_plano: "(estimativa minha)" no dia marcado pela estimativa.
--   6. agenda_gestor_dito: *gestor, só propor* / *gestor, pode marcar* (gestor_so_propor, a ação gestor, desfazível).
--   7. agenda_desfazer: os ramos estimar, dupla e gestor; e o que era de quem saiu da equipe não volta (restaura só o que cabe e
--      diz o resto).
--   8. agenda_saude: o bloco gestor com os zeros (entram no ok) e os números; e o erro do fator só com as medidas com fator.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_rodada.sql e agenda_fase7a_replay.sql; registradas em
-- notas-fase77a.md, P7):
--   · agenda_textos_do_fechamento é recriada aqui (a spec põe vagas_garantidas "na saída" de _agenda_linhas_do_fechamento, que
--     devolve uma LISTA de linhas; o objeto que o Secretário lê é o de agenda_textos_do_fechamento). Quem recriar depois (o 7f,
--     pelo registro §2) copia DESTA migration.
--   · O aviso ao dono do que a rodada mudou não é chamado daqui: o montador do aviso do lote P4 é TypeScript (task-automations,
--     passo agenda-aviso, no tique seguinte da vigia), e ele já conta toda ação de plano executada da vigia ou do motor ainda não
--     contada — o que o gestor marcar (origem vigia) sai na mensagem seguinte, em até 8 minutos. A rodada grava acoes e mudou.
--   · O foco ligado lê "fora" da última conta de verdade do motor (a proposta de modo ligado mais nova que falou da OS, em 8
--     dias): o foco é STABLE e não pode rodar o motor.
--   · O *desfaz* que só traria de volta quem saiu da equipe é recusado sem mudar nada (status saiu_da_equipe), e o parcial diz
--     quem não voltou: sem portão — é a correção do vaivém de 30/10, que acontece com as Fases 1–6 ligadas, gestor ligado ou não.
--   · Os zeros do bloco gestor que contam o que o gestor muda sozinho contam a partir de marcar_sozinho_desde (o OK de ligar);
--     prazo_vencido_sem_mostrar fica fora do ok (a spec: "aqui só se conta").
--   · A nota de dupla do foco diz o porquê em palavras ("banco de baterias", "127/220 V energizado", "içamento"), não o trecho
--     normalizado do nome do serviço.
--
-- O QUE NÃO MUDA: nenhuma tabela, coluna, lista fechada ou dado; o motor, a prontidão, a classe, os meios e a vigia (nenhum bloco
-- novo neles). Com os modos do gestor desligados (como a linha nasce no P1), a rodada não faz nada, o fechamento e o foco plano
-- saem como antes (byte a byte, R9/R3), o *desfaz* das ações de antes só muda para quem saiu da equipe e a saúde ganha a chave
-- gestor (zeros).
--
-- ORDEM DE LIGAR: depois de 20261031100500 (P6). Aplicar sozinha não muda o que a agenda faz (os modos do gestor estão
-- desligados na linha); o job agenda-gestor passa a rodar e devolve {rodou: false}. A migration de dado 20261031100990 põe os 5
-- modos em sombra (a partir daí, o "eu marcaria assim" todo dia útil às 16:52); o ligar é o roteiro de fila-do-dono/fase7a-oks.md.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7a_rodada.sql e agenda_fase7a_replay.sql (begin/rollback). Na bancada:
-- node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100600_agenda_fase7a_rodada.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261031100600', 'agenda_fase7a_rodada');"
--   Depois: no 1º tique (o próximo :07/:22/:37/:52), conferir que o job rodou as duas instruções:
--   npx supabase@2.111.0 db query --linked -e "select status, return_message, start_time from cron.job_run_details
--     where jobid = (select jobid from cron.job where jobname = 'agenda-gestor') order by start_time desc limit 3;"
--
-- DESFAZER: o job — select cron.unschedule('agenda-gestor'); o que o gestor faz — os modos (spec §10, "Desfazer"). Para tirar o
-- código: recriar as 6 recriadas com o corpo da origem (a cópia sem os blocos "-- FASE 7:") e apagar as 12 novas.
--
-- IDEMPOTENTE: create or replace function, o job desagendado e agendado de novo pelo nome, revoke/grant e comment.

-- ── 1. As funções novas ────────────────────────────────────────────────────────────────────────────────────────

-- O porquê de uma OS de fora numa palavra só, para o dono (spec §6.1: "esperando o cliente", "orçamento sem virar OS",
-- "esperando o sinal", "precisa de você em campo", "material"), a partir do motivo do motor (agenda_propor.fora) ou da classe.
-- A ordem da lista (_agenda_gestor_motivo_ordem) é a de como o fechamento agrupa: do que mais segura para o que menos.
create or replace function public._agenda_gestor_motivo_texto(p_motivo text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_motivo = 'cliente' then 'esperando o cliente'
    when p_motivo = 'orcamento' then 'orçamento sem virar OS'
    when p_motivo = 'sinal' then 'esperando o sinal'
    when p_motivo in ('padrao_do_dono', 'so_com_voce', 'dono') then 'precisa de você em campo'
    when p_motivo in ('material', 'compra', 'compre_ate', 'sem_previsao', 'conferir_material', 'material_nao_conferido') then 'material'
    when p_motivo = 'escopo' then 'escopo em aberto'
    when p_motivo = 'bem' then 'esperando o barco ou o motorhome'
    when p_motivo in ('espera', 'nao_cabe') then 'esperando a sua decisão'
    when p_motivo in ('situacao', 'estimativa', 'duracao') then 'falta saber os dias'
    when p_motivo in ('sem_encaixe', 'sem_reserva', 'fixar_nao_cabe', 'depois', 'fixar_recusado') then 'sem lugar na agenda'
    else 'outro motivo'
  end;
$function$;

comment on function public._agenda_gestor_motivo_texto(text) is
  'Agenda de Produção (Fase 7a, P7): o porquê de uma OS de fora numa palavra só, para o dono — cliente "esperando o cliente", orcamento "orçamento sem virar OS", sinal "esperando o sinal", padrao_do_dono/so_com_voce/dono "precisa de você em campo", o material "material", escopo, bem, a decisão crítica, os dias que faltam saber, sem lugar; o resto "outro motivo". IMMUTABLE.';

create or replace function public._agenda_gestor_motivo_ordem(p_texto text)
 returns int
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(array_position(array['esperando o cliente', 'orçamento sem virar OS', 'esperando o sinal', 'precisa de você em campo',
                                       'material', 'escopo em aberto', 'esperando o barco ou o motorhome', 'esperando a sua decisão',
                                       'falta saber os dias', 'sem lugar na agenda', 'outro motivo'], p_texto), 99);
$function$;

comment on function public._agenda_gestor_motivo_ordem(text) is
  'Agenda de Produção (Fase 7a, P7): a ordem dos grupos de fora (a de _agenda_gestor_motivo_texto: do que mais segura para o que menos). IMMUTABLE.';

-- A faixa de um serviço numa frase: "ter 03 a ter 10/11" (o mesmo mês sem o mês no 1º dia), "ter 03/11" (um dia só).
create or replace function public._agenda_gestor_faixa(p_de date, p_ate date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_de is null then null
              when p_ate is null or p_ate = p_de then public._dia_curto(p_de)
              else case when to_char(p_de, 'YYYYMM') = to_char(p_ate, 'YYYYMM') then public._agenda_dia_sem_mes(p_de)
                        else public._dia_curto(p_de) end || ' a ' || public._dia_curto(p_ate) end;
$function$;

comment on function public._agenda_gestor_faixa(date, date) is
  'Agenda de Produção (Fase 7a, P7): "ter 03 a ter 10/11"; "sex 30/10 a ter 03/11"; um dia só, "ter 03/11". IMMUTABLE.';

-- Quem vai num serviço, sem o dono (ele abre e fecha; não é "pessoa" do serviço): os nomes de quem faz meio-dia de turno, de
-- quem faz mais para quem faz menos, depois por quem entra primeiro ("Roberto e João"). Só o dono = "você".
create or replace function public._agenda_gestor_pessoas(p_alocs jsonb)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(nullif(public._agenda_lista(array(
           select t.nome from (
             select a ->> 'nome' as nome, count(*) as n,
                    min((a ->> 'dia') || case when a ->> 'turno' = 'manha' then '0' else '1' end) as primeiro
               from jsonb_array_elements(coalesce(p_alocs, '[]'::jsonb)) a
              where (a ->> 'payee_id')::uuid is distinct from public._agenda_dono(null)
                and coalesce(a ->> 'presenca', 'turno') = 'turno'
              group by a ->> 'nome') t
            order by t.n desc, t.primeiro, t.nome), null), ''), 'você');
$function$;

comment on function public._agenda_gestor_pessoas(jsonb) is
  'Agenda de Produção (Fase 7a, P7): quem faz o serviço, pelas alocações de um item do motor [{payee_id, nome, dia, turno, presenca}] — sem o dono, só o meio-dia de turno, de quem faz mais meios-dias para quem faz menos (desempate: quem entra primeiro): "Roberto e João". Só o dono = "você".';

-- Os itens críticos a comprar de uma OS pela prontidão de hoje (o que o "compre até" do texto conta): {n, compre_ate} — os
-- itens críticos em falta com "compre até" (o mais cedo deles). Nada a comprar = {n: 0}.
create or replace function public._agenda_gestor_compra_da_os(p_os uuid, p_hoje date)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select jsonb_build_object('n', count(*), 'compre_ate', min((e ->> 'compre_ate')::date))
    from jsonb_array_elements(coalesce(public.os_prontidao(p_os, p_hoje) #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, true) and e ->> 'situacao' = 'falta' and e ->> 'compre_ate' is not null;
$function$;

comment on function public._agenda_gestor_compra_da_os(uuid, date) is
  'Agenda de Produção (Fase 7a, P7): {n, compre_ate} — os itens críticos em falta com "compre até" na prontidão da OS em p_hoje (o mais cedo deles). Dentro da simulação da sombra, a prontidão com as regras do gestor.';

-- O "eu marcaria assim" (spec §3.1 item 3, §5.7, §6.1): o MESMO motor, com as regras do gestor ligadas só dentro desta função
-- (a variável de sessão agenda.gestor = 'sombra', que _agenda_gestor_regra lê; desligada no fim, e o rollback de qualquer erro a
-- desfaz), sobre a carteira inteira sem compromisso de hoje em diante (as com reserva também): agenda_propor('os', …,
-- persistir false) — a simulação da Fase 2, que não grava nada — e as perguntas do gestor em modo seco
-- (_agenda_gestor_perguntas_da_os). Grava no diário do dia (_agenda_gestor_dia_gravar): sombra = {itens, reservas, fora,
-- perguntas, md5} e texto_sombra (a linha do fechamento, ≤ 640). Só roda com algum dos modos marcar, encaixe ou revisao em
-- sombra; senão {pulado}. Passo diário de agenda_gestor_rodar.
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
  perform public._agenda_gestor_dia_gravar(p_hoje, 'sombra', v_som, p_agora);
  perform public._agenda_gestor_dia_gravar(p_hoje, 'texto_sombra', to_jsonb(v_txt), p_agora);
  return jsonb_build_object('itens', jsonb_array_length(v_itens), 'reservas', jsonb_array_length(v_res), 'fora', v_nf,
                            'perguntas', jsonb_array_length(v_perg), 'md5', v_som ->> 'md5', 'texto', v_txt);
end;
$function$;

comment on function public._agenda_gestor_sombra(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P7; spec §3.1 item 3, §5.7, §6.1): o "eu marcaria assim" — com algum dos modos marcar, encaixe ou revisao em sombra (senão {pulado}), o mesmo motor com as regras do gestor ligadas só dentro da função (agenda.gestor = ''sombra''; desligada no fim e no erro): agenda_propor(''os'', a carteira sem compromisso de hoje em diante, persistir false) e as perguntas do gestor em modo seco. Grava no diário do dia: sombra = {calculado_em, modos, itens [{os, numero, cliente, de, ate, dias, pessoas, fonte, meios, compre_ate, itens_a_comprar, alerta_dupla}], reservas, fora [{os, numero, cliente, motivo, grupo, texto}], perguntas [{os, numero, cliente, tipo, chave, variante, curto, proposta_dias, veto_ate, texto}], md5} e texto_sombra ("Agenda em teste (nada mudou): eu marcaria assim — Lenine de ter 03 a ter 10/11, Roberto e João (6 dias, estimativa minha); … Antes de marcar eu perguntaria: Giancarlo (10 diárias pela estimativa), … Continuam fora 6: esperando o cliente (3), … *agenda gestor* mostra tudo.", ≤ 640). Nada mais é gravado (a simulação não grava alocação, proposta, ação nem pergunta). Invoker, sem grant: só a rodada do gestor a chama.';

-- As perguntas do gestor antes de marcar (spec §5.7): passo diário. Com o gestor que marca LIGADO de verdade, para cada OS da
-- carteira sem compromisso de hoje em diante, _agenda_gestor_perguntas_da_os grava a pergunta (situacao/estimativa, com o
-- prazo). Em sombra nada é gravado aqui: as perguntas secas vão no "eu marcaria assim" (_agenda_gestor_sombra). O erro de uma
-- OS vai a app_error_logs (gestor:perguntas) e as outras seguem.
create or replace function public._agenda_gestor_perguntas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_modo   text;
  v_os     uuid;
  r        jsonb;
  v_n      int := 0;
  v_perg   int := 0;
  v_novas  int := 0;
  v_erros  int := 0;
  v_estado text;
  v_msg    text;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_perguntas: sem o dia ou a hora' using errcode = '22004';
  end if;
  v_modo := public._agenda_gestor_modo('marcar');
  if v_modo <> 'ligado' then
    return jsonb_build_object('pulado', true, 'modo', v_modo,
                              'motivo', case when v_modo = 'sombra' then 'em teste: as perguntas vão secas no "eu marcaria"'
                                             else 'o gestor está desligado' end);
  end if;
  for v_os in select k.service_order_id from public.os_carteira(p_hoje) k
               where not public._agenda_os_tem_dia(k.service_order_id, p_hoje)
               order by k.numero, k.service_order_id loop
    begin
      r := public._agenda_gestor_perguntas_da_os(v_os, p_hoje, p_agora, false);
      v_n := v_n + 1;
      if coalesce((r ->> 'perguntou')::boolean, false) then
        v_perg := v_perg + 1;
        if coalesce((r ->> 'nova')::boolean, false) then
          v_novas := v_novas + 1;
        end if;
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      perform public.log_app_error('db', format('gestor da agenda, pergunta antes de marcar: %s', v_msg), 'agenda',
                                   'gestor:perguntas', 'error',
                                   jsonb_build_object('os', v_os, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;
  return jsonb_build_object('os', v_n, 'perguntas', v_perg, 'novas', v_novas, 'erros', v_erros);
end;
$function$;

comment on function public._agenda_gestor_perguntas(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P7; spec §5.7): passo diário do gestor — com o modo marcar ligado de verdade (fora disso {pulado}: em sombra as perguntas vão secas no "eu marcaria assim"), para cada OS da carteira sem compromisso de hoje em diante, _agenda_gestor_perguntas_da_os(…, p_seco false) grava a pergunta situacao/estimativa com o prazo (spec §6.3). {os, perguntas, novas, erros}; o erro de uma OS vai a app_error_logs (gestor:perguntas) e as outras seguem. Invoker, sem grant.';

-- Os dias marcados de uma OS que vêm da estimativa do gestor (spec §5.7, _agenda_ver_plano): as linhas do dia (agenda_linhas_do_dia)
-- da OS com alocação de compromisso vigente naquele dia com duracao_fonte orcamento ganham "(estimativa minha)" depois das
-- pessoas. Sem portão: a fonte orcamento só existe se o gestor marcou pela estimativa (desligar o gestor depois não muda o que
-- foi marcado assim).
create or replace function public._agenda_plano_estimativa(p_linhas jsonb, p_dia date)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(case when not coalesce((x ->> 'reserva')::boolean, false)
                                      and x ->> 'os' is not null
                                      and exists (select 1 from public.agenda_alocacoes a
                                                   where a.service_order_id = (x ->> 'os')::uuid and a.dia = p_dia
                                                     and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                                                     and a.duracao_fonte = 'orcamento')
                                      and right(x ->> 'texto', 19) <> '(estimativa minha)'
                                 then jsonb_set(x, '{texto}', to_jsonb((x ->> 'texto') || ' (estimativa minha)'))
                                 else x end order by o), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) with ordinality t(x, o);
$function$;

comment on function public._agenda_plano_estimativa(jsonb, date) is
  'Agenda de Produção (Fase 7a, P7): as linhas de agenda_linhas_do_dia de p_dia — a da OS com alocação de compromisso vigente nesse dia com duracao_fonte orcamento (o gestor marcou pela estimativa do orçamento) termina "(estimativa minha)" depois das pessoas; a reserva e as outras, como vieram. Sem portão.';

-- O foco gestor (spec §6.2): o que o gestor da agenda marcou (ligado) ou marcaria (em teste) e por quê, o que ele perguntou
-- antes, o que fica de fora, as compras da semana (P10), os orçamentos que caberiam (P12) e como ele conta. Só lê: o diário do
-- gestor (agenda_gestor_dia), o plano, as perguntas, a última conta do motor e os parâmetros. STABLE.
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
                                    then format(' Pode precisar de dupla (%s): diga *%s com dupla*.',
                                                public._agenda_gestor_dupla_texto(x -> 'alerta_dupla'), x ->> 'cliente')
                                    else '' end);
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
      v_l := v_l || format('• %s: %s, %s — %s (estimativa minha).%s',
                           coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                                       join public.clients cl on cl.id = so.client_id where so.id = r.os), 'serviço'),
                           public._agenda_gestor_faixa(r.de, r.ate), public._agenda_gestor_pessoas(r.alocs),
                           public._agenda_dias(r.meios::numeric / 2),
                           coalesce((select format(' Pode precisar de dupla (%s): diga *%s com dupla*.',
                                                   public._agenda_gestor_dupla_texto(d.a), public._agenda_nome_curto(cl.name))
                                       from (select public.os_duracao_sugerida(r.os) -> 'alerta_dupla' as a) d,
                                            public.service_orders so join public.clients cl on cl.id = so.client_id
                                      where so.id = r.os and jsonb_typeof(d.a) = 'object'), ''));
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
        coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                    join public.clients cl on cl.id = so.client_id where so.id = r.service_order_id), 'serviço'),
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
                                                 'grupo', public._agenda_gestor_motivo_texto(t.motivo)) order by t.numero), '[]'::jsonb)
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
    v_l := v_l || array(select '• ' || (e ->> 'texto') from jsonb_array_elements(v_comp) with ordinality t(e, o)
                         where nullif(btrim(e ->> 'texto'), '') is not null order by o);
  end if;
  select g.orcamentos into v_orc from public.agenda_gestor_dia g
   where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.orcamentos <> '[]'::jsonb order by g.dia desc limit 1;
  if jsonb_array_length(coalesce(v_orc, '[]'::jsonb)) > 0 then
    v_l := v_l || 'Se aprovar:'::text;
    v_l := v_l || array(select '• ' || (e ->> 'texto') from jsonb_array_elements(v_orc) with ordinality t(e, o)
                         where nullif(btrim(e ->> 'texto'), '') is not null order by o);
  end if;

  -- 7. como eu conto (todos os números dos parâmetros)
  v_l := v_l || format('Como eu conto: estimativa pelo valor do orçamento (R$ %s de mão de obra por diária, sem deslocamento); '
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

  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('modo', v_ef, 'so_propor', cf.gestor_so_propor, 'conta_de', v_sdia,
                                                        'sombra', v_s, 'fora', v_fora));
end;
$function$;

comment on function public._agenda_ver_gestor(date) is
  'Agenda de Produção (Fase 7a, P7; spec §6.2): o foco gestor de agenda_ver — (1) o estado: "O gestor está em teste desde qui 29/10: calcula o que marcaria, mas não muda nada." / "Eu marco sozinho desde ter 03/11 e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz." / "Desde sex 06/11 você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta." / desligado; (2) em teste, "Eu marcaria:" pela última conta do diário (agenda_gestor_dia.sombra), um por linha ("• Lenine: ter 03 a ter 10/11, Roberto e João — 6 dias (estimativa minha). Pode precisar de dupla (banco de baterias): diga *Lenine com dupla*."); ligado, "Marquei nos últimos 7 dias:" (as OS com compromisso vigente pela estimativa); (3) "Antes de marcar eu perguntaria:" (teste) ou "Perguntei antes de marcar:" com o prazo ("• Giancarlo: 10 diárias pela estimativa — sem resposta até sex 30/10 18:00, marco assim."); (4) "Fora:" agrupado pelo porquê ("esperando o cliente: Kalmar (2) e Rodrigo; …"; ligado, pela última conta de verdade do motor em 8 dias); (5) "Compras da semana:" e (6) "Se aprovar:" pelo diário (agenda_gestor_dia.compras e .orcamentos, [{texto}], de até 3 dias; o P10 e o P12 gravam); (7) "Como eu conto:" com os parâmetros. {ok, texto (≤ texto_max), dados}. STABLE, invoker.';

-- O porquê da nota de dupla numa palavra (os gatilhos de dupla_gatilhos/dupla_notas: banco_cc, bateria_pesada, ca_energizado,
-- icamento, confinado): "Pode precisar de dupla (banco de baterias)".
create or replace function public._agenda_gestor_dupla_texto(p_alerta jsonb)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case coalesce(p_alerta ->> 'motivo', p_alerta ->> 'nota')
    when 'banco_cc' then 'banco de baterias'
    when 'bateria_pesada' then 'bateria pesada'
    when 'ca_energizado' then '127/220 V energizado'
    when 'icamento' then 'içamento'
    when 'confinado' then 'espaço apertado'
    else 'pelo tipo de serviço' end;
$function$;

comment on function public._agenda_gestor_dupla_texto(jsonb) is
  'Agenda de Produção (Fase 7a, P7): o porquê da nota de dupla (alerta_dupla de os_duracao_sugerida) numa palavra — banco_cc "banco de baterias", bateria_pesada "bateria pesada", ca_energizado "127/220 V energizado", icamento "içamento", confinado "espaço apertado". IMMUTABLE.';

-- A palavra *gestor, só propor* / *gestor, pode marcar* (spec §3.2, §5.7, §6.4): só o dono (_autor_da_agenda). Grava
-- gestor_so_propor e gestor_so_propor_em e a ação gestor (desfazível por desfazer_validade). Dizer de novo = "Já estava assim."
create or replace function public.agenda_gestor_dito(p_autor uuid, p_so_propor boolean, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  v_autor  uuid;
  v_antes  jsonb;
  v_depois jsonb;
  v_txt    text;
  v_acao   uuid;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_gestor_dito: sem o dia ou a hora' using errcode = '22004';
  end if;
  if p_so_propor is null then
    raise exception 'agenda_gestor_dito: diga se o gestor só propõe ou pode marcar' using errcode = '22004';
  end if;
  v_autor := public._autor_da_agenda(p_autor);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  select * into cf from public.agenda_config where id for update;
  if cf.gestor_so_propor = p_so_propor then
    return jsonb_build_object('ok', true, 'mudou', false, 'so_propor', p_so_propor, 'texto', 'Já estava assim.');
  end if;
  v_antes := jsonb_build_object('gestor_so_propor', cf.gestor_so_propor, 'gestor_so_propor_em', cf.gestor_so_propor_em);
  v_depois := jsonb_build_object('gestor_so_propor', p_so_propor, 'gestor_so_propor_em', p_agora);
  v_txt := case when p_so_propor
                then 'Combinado: até você dizer *gestor, pode marcar*, eu só sugiro — não marco nem mudo nada sozinho do jeito novo (o que eu fazia antes de 29/10 continua).'
                else 'Voltei a marcar sozinho; o que eu marcar vem no seu fechamento, com *desfaz*.' end;
  update public.agenda_config set gestor_so_propor = p_so_propor, gestor_so_propor_em = p_agora, atualizado_em = p_agora,
                                  atualizado_por = v_autor
   where id;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, antes, depois, texto, motivo, autor, desfazivel_ate)
  values (p_agora, p_hoje, true, 'dono', 'gestor', v_antes, v_depois, left(v_txt, 400),
          case when p_so_propor then 'você disse: gestor, só propor' else 'você disse: gestor, pode marcar' end,
          v_autor, p_agora + cf.desfazer_validade)
  returning id into v_acao;
  return jsonb_build_object('ok', true, 'mudou', true, 'so_propor', p_so_propor, 'acao_id', v_acao, 'texto', v_txt);
end;
$function$;

comment on function public.agenda_gestor_dito(uuid, boolean, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P7; spec §3.2, §6.4): a palavra do dono *gestor, só propor* (p_so_propor true: as regras e os jobs novos do gestor voltam a teste — _agenda_gestor_modo dá sombra ao que estava ligado; o que as Fases 1–6 fazem continua) e *gestor, pode marcar* (false). Só o administrador (_autor_da_agenda: 42501). Grava gestor_so_propor, gestor_so_propor_em e a ação gestor (origem dono, antes/depois, desfazível por desfazer_validade: agenda_desfazer volta). Dizer de novo = {ok, mudou false, texto "Já estava assim."}. Security definer, só o service_role.';

-- A rodada do gestor da agenda (spec §3.1 item 13, §5.7): o job agenda-gestor do pg_cron, a cada 15 min (07/22/37/52, fora dos
-- :00/:15/:30/:45 da vigia), de 07:07 a 20:52 de Brasília, seg a sáb. Os passos, cada um _agenda_gestor_<passo>(date,
-- timestamptz) → jsonb, na ordem: os de todo tique (vetos, encaixe, bem, sinal, puxar) e, no 1º tique de dia útil a partir de
-- gestor_hora_revisao, os diários (perguntas, compre_ate, revisao, fichas, orcamentos, sabado, equipe, sombra). O passo cuja
-- função ainda não existe é pulado (os pacotes seguintes só CRIAM o passo). Cada passo no seu bloco: o erro vai a app_error_logs
-- (gestor:<passo>) e a rodada segue; o tempo estourado (query_canceled, que "others" não pega) registra, grava a rodada e
-- encerra. Uma linha em agenda_vigia_rodadas (rotina gestor) por rodada que rodou. Com os 4 modos do gestor desligados, nada.
create or replace function public.agenda_gestor_rodar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_tique   constant text[] := array['vetos', 'encaixe', 'bem', 'sinal', 'puxar'];
  c_diarios constant text[] := array['perguntas', 'compre_ate', 'revisao', 'fichas', 'orcamentos', 'sabado', 'equipe', 'sombra'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_modos   jsonb;
  v_diaria  boolean;
  v_passos  text[];
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_parou   text;
  v_estado  text;
  v_msg     text;
  v_acoes   int;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada do gestor.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  -- uma rodada por vez (o tique seguinte que chega com esta rodando não espera: sai)
  if not pg_try_advisory_xact_lock(hashtext('agenda_gestor')) then
    return jsonb_build_object('rodou', false, 'ocupado', true);
  end if;
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                'revisao', public._agenda_gestor_modo('revisao'), 'compre_ate', public._agenda_gestor_modo('compre_ate'),
                                'vaga', public._agenda_gestor_modo('vaga'), 'so_propor', cf.gestor_so_propor);
  if v_modos ->> 'marcar' = 'desligado' and v_modos ->> 'encaixe' = 'desligado' and v_modos ->> 'revisao' = 'desligado'
     and v_modos ->> 'compre_ate' = 'desligado' then
    return jsonb_build_object('rodou', false, 'modos', v_modos);
  end if;
  -- os passos diários: no 1º tique de dia útil a partir de gestor_hora_revisao (o dia está numa rodada gestor com "diaria")
  v_diaria := public.agenda_dia_util(p_hoje)
              and (p_agora at time zone 'America/Sao_Paulo')::time >= cf.gestor_hora_revisao
              and not exists (select 1 from public.agenda_vigia_rodadas x
                               where x.rotina = 'gestor' and x.p_hoje = p_hoje and x.contagens ? 'diaria');
  v_passos := c_tique || case when v_diaria then c_diarios else '{}'::text[] end;
  v_acoes := (select count(*) from public.agenda_acoes a where a.executada);

  foreach v_passo in array v_passos loop
    if to_regprocedure(format('public.%I(date, timestamp with time zone)', '_agenda_gestor_' || v_passo)) is null then
      v_cont := v_cont || jsonb_build_object(v_passo, jsonb_build_object('pulado', true, 'motivo', 'ainda não existe'));
      continue;
    end if;
    begin
      execute format('select public.%I($1, $2)', '_agenda_gestor_' || v_passo) into v_r using p_hoje, p_agora;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception
      when query_canceled then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_parou := v_passo;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('gestor da agenda, passo %s: o tempo da rodada acabou (%s)', v_passo, v_msg),
                                     'agenda', 'gestor:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora,
                                                        'tempo_max', cf.gestor_tempo_max::text));
        exit;
      when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('gestor da agenda, passo %s: %s', v_passo, v_msg), 'agenda',
                                     'gestor:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;

  v_acoes := (select count(*) from public.agenda_acoes a where a.executada) - v_acoes;
  -- os diários só contam como feitos se a rodada não parou no tempo (senão o tique seguinte tenta de novo)
  v_cont := v_cont || jsonb_build_object('modos', v_modos, 'falhas', v_falhas, 'acoes', v_acoes,
                                         'mudou', v_acoes > 0)
            || case when v_diaria and v_parou is null then jsonb_build_object('diaria', true) else '{}'::jsonb end
            || case when v_parou is not null then jsonb_build_object('parou_no', v_parou) else '{}'::jsonb end;
  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia, v_cont, least(v_erros, 32767),
          greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int), 'gestor', cf.modo_equipe, cf.modo_diaria);
  return jsonb_build_object('rodou', true, 'modos', v_modos, 'diaria', v_diaria and v_parou is null, 'parou_no', v_parou,
                            'acoes', v_acoes, 'erros', v_erros, 'falhas', v_falhas, 'contagens', v_cont);
end;
$function$;

comment on function public.agenda_gestor_rodar(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P7; spec §3.1 item 13, §5.7): a rodada do gestor da agenda (o job agenda-gestor do pg_cron, ''7,22,37,52 10-23 * * 1-6'', com o statement_timeout de gestor_tempo_max). Passos _agenda_gestor_<passo>(date, timestamptz) → jsonb: de todo tique vetos, encaixe, bem, sinal, puxar; diários (no 1º tique de dia útil a partir de gestor_hora_revisao, uma vez: a rodada gestor do dia com "diaria") perguntas, compre_ate, revisao, fichas, orcamentos, sabado, equipe, sombra. O passo cuja função ainda não existe = {pulado}. Erro de um passo → app_error_logs (gestor:<passo>) e segue; query_canceled → registra, grava a rodada (parou_no) e encerra (os diários tentam de novo no tique seguinte). Com marcar, encaixe, revisao e compre_ate desligados = {rodou: false} (nada gravado). Uma rodada por vez (pg_try_advisory_xact_lock: a outra sai com {rodou: false, ocupado}). Uma linha em agenda_vigia_rodadas (rotina gestor) com as contagens de cada passo, os modos, as falhas, as ações executadas na rodada (acoes, mudou), os erros e a duração. O aviso ao dono do que mudou sai pelo passo agenda-aviso do task-automations no tique seguinte (ele já conta toda ação de plano executada da vigia/motor ainda não contada). Security definer, só o service_role.';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7:") ──────────────────────────
-- Fora dos blocos nenhuma linha muda (o R9 de supabase/tests/agenda_fase7a_rodada.sql confere). Quem recriar de novo qualquer
-- uma delas copia DESTA migration (fase7-registro.md §2: agenda_desfazer no 7b P3; agenda_saude no 7b P5; agenda_ver no 7c P6;
-- _agenda_linhas_do_fechamento, agenda_textos_do_fechamento e _agenda_ver_plano, quem vier).

-- _agenda_linhas_do_fechamento (de 20261030100500_agenda_correcao_revisao.sql)
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

  -- (e) uma pergunta de fato, a que perde primeiro (cada pergunta aparece em até perguntas_vezes_max fechamentos)
  -- FASE 3: entram também concluir, entrega, equipe_resposta e diaria_ligar (não críticas)
  for m in select unnest(array['ligado', 'sombra']) loop
    select count(*) into v_n from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
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
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte.';

-- agenda_textos_do_fechamento (de 20261025100500_agenda_fase2_leituras.sql)
create or replace function public.agenda_textos_do_fechamento(p_hoje date default public._hoje_brt(), p_dia date default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_pn     jsonb;
  v_dia    date;
  v_marc   jsonb;
  v_prox   jsonb;
  v_prontos jsonb;
  v_esp    int;
  v_plano  boolean;
  v_seg    date;
  v_cauda  text;
  v_sem    text[] := '{}';
  v_l      text;
  k        int;
  c_max    constant int := 160;
  -- FASE 7: (7a P7) as vagas da agenda no fechamento
  v_f7_lin jsonb;
  v_f7_n   int;
  -- FASE 7: fim
begin
  if p_hoje is null then
    raise exception 'agenda_textos_do_fechamento: sem o dia de hoje' using errcode = '22004';
  end if;
  if c.modo_leitura = 'desligado' then
    return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', null, 'semana_que_vem', '[]'::jsonb,
                              'dia_do_plano', false,
                              -- FASE 2: com a leitura desligada a agenda inteira cala
                              'linhas', '[]'::jsonb);
  end if;
  v_dia := coalesce(p_dia, p_hoje + 1);
  v_pn := public._agenda_painel(p_hoje);
  v_plano := extract(isodow from p_hoje)::int = c.dia_do_plano;

  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_prontos from jsonb_array_elements(v_pn -> 'oss') e where e ->> 'grupo' = 'pronto';
  select count(*) into v_esp from jsonb_array_elements(v_pn -> 'oss') e where (e ->> 'dono_trava')::boolean;

  -- A cauda do "Amanhã" sem nada marcado. Se a agenda vê algo marcado no dia, não há cauda (o Secretário diz o dia).
  -- (FASE 2: em 'ligado' o marcado é o plano — _agenda_marcados.)
  v_marc := public._agenda_marcados(v_dia, v_dia, p_hoje, null, (v_pn ->> 'dono_usuario')::uuid);
  if jsonb_array_length(v_marc) = 0 then
    v_cauda := 'nada marcado; '
      || case when jsonb_array_length(v_prontos) > 0 then 'prontos para começar: ' || public._agenda_nomes(v_prontos, 3)
              when (v_pn #>> '{backlog,n}')::int = 0 then 'nenhum serviço na fila'
              when v_esp > 0 then format('nenhum serviço pronto, %s esperando você', v_esp)
              else 'nenhum serviço pronto ainda' end
      || ' (*agenda*)';
  end if;

  -- Só no dia do plano (quinta): até 3 linhas da semana que vem, cada uma com até 160 caracteres.
  -- FASE 2: com a agenda automática ligada a projeção não sai: a linha "semana" do publicado (linhas) a substitui.
  if v_plano and c.modo_proposta <> 'ligado' then
    v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1) + 7;
    v_prox := public._agenda_marcados(v_seg, v_seg + 5, p_hoje, null, (v_pn ->> 'dono_usuario')::uuid);
    for k in reverse 3 .. 1 loop
      v_l := 'Semana que vem (projeção): '
             || case when jsonb_array_length(v_prox) = 0 then 'nada marcado'
                     else public._agenda_plural(jsonb_array_length(v_prox), 'marcado', 'marcados') || ' ('
                          || public._agenda_lista(array(select e ->> 'nome' from jsonb_array_elements(v_prox) with ordinality t(e, o)
                                                         order by o), k) || ')' end
             || case when (v_pn #>> '{backlog,n}')::int = 0 then '; nenhum serviço na fila.'
                     else '; ' || public._agenda_plural((v_pn #>> '{backlog,n}')::int, 'serviço na fila', 'serviços na fila')
                          || ', ' || public._agenda_fila_faixa(v_pn)
                          || case when (v_pn ->> 'comprometivel')::numeric > 0
                                  then format(' (~%s por semana, %s)', public._agenda_num((v_pn ->> 'comprometivel')::numeric, 1),
                                              case when (v_pn #>> '{cap,conta_dono}')::boolean then 'contando você' else 'sem contar você' end)
                                  else '' end || '.' end;
      exit when char_length(v_l) <= c_max;
    end loop;
    v_sem := v_sem || v_l;
    for k in reverse 3 .. 1 loop
      v_l := case when jsonb_array_length(v_prontos) > 0 then 'Prontos para começar: ' || public._agenda_nomes(v_prontos, k)
                  else 'Nenhum pronto para começar' end
             || case when v_esp > 0 then '; o que falta de você está em *agenda*.'
                     when jsonb_array_length(v_prontos) > 0 then '.' else ' ainda.' end;
      exit when char_length(v_l) <= c_max;
    end loop;
    v_sem := v_sem || v_l;
    v_l := public._agenda_livre_linha(v_pn, false);
    if v_l is not null then v_sem := v_sem || v_l; end if;
    v_sem := array(select x from unnest(v_sem) x where char_length(x) <= c_max);
  end if;

  -- FASE 7: (7a P7) as vagas que a agenda tem garantidas no fechamento (spec §5.7 item 3, §7): com modo_vaga_fechamento
  -- ligado, fechamento_vagas_agenda (+1 com alguma linha ligada de decisão de perda ≥ 80 — a decisão crítica e a compra urgente —,
  -- até 2) em vagas_garantidas; em sombra, vagas_garantidas = 0 e vaga_teria = as que teria (o Secretário põe no detalhe).
  -- Desligado, a saída de antes, byte a byte. As linhas são lidas uma vez só (a mesma lista vai em linhas).
  if public._agenda_gestor_modo('vaga') <> 'desligado' then
    v_f7_lin := public._agenda_linhas_do_fechamento(p_hoje);
    v_f7_n := least(2, c.fechamento_vagas_agenda
                       + case when exists (select 1 from jsonb_array_elements(v_f7_lin) x
                                            where x ->> 'modo' = 'ligado' and x ->> 'tipo' in ('decisao', 'compras')
                                              and (x ->> 'perda')::int >= 80) then 1 else 0 end);
    return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', v_cauda, 'semana_que_vem', to_jsonb(v_sem),
                              'dia_do_plano', v_plano, 'dia', v_dia,
                              'dados', jsonb_build_object('prontos', jsonb_array_length(v_prontos), 'esperando_voce', v_esp,
                                                          'fila', v_pn -> 'backlog', 'livre', v_pn -> 'livre'),
                              'linhas', v_f7_lin,
                              'vagas_garantidas', case when public._agenda_gestor_modo('vaga') = 'ligado' then v_f7_n else 0 end,
                              'vaga_teria', case when public._agenda_gestor_modo('vaga') = 'sombra' then v_f7_n end);
  end if;
  -- FASE 7: fim
  return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', v_cauda, 'semana_que_vem', to_jsonb(v_sem),
                            'dia_do_plano', v_plano, 'dia', v_dia,
                            'dados', jsonb_build_object('prontos', jsonb_array_length(v_prontos), 'esperando_voce', v_esp,
                                                        'fila', v_pn -> 'backlog', 'livre', v_pn -> 'livre'),
                            -- FASE 2: as linhas da agenda (decisões, o dia, a semana, o que mudou, uma pergunta)
                            'linhas', public._agenda_linhas_do_fechamento(p_hoje));
end;
$function$;

comment on function public.agenda_textos_do_fechamento(date, date) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5): as linhas da agenda no fechamento das 17:30 — cauda_amanha (o "Amanhã" sem nada marcado: "nada marcado; nenhum serviço pronto, 7 esperando você (*agenda*)" ou "nada marcado; prontos para começar: …"; null quando a agenda vê algo marcado em p_dia — em ''ligado'', o plano), só quando isodow(p_hoje) = dia_do_plano e a agenda automática não está ligada, até 3 linhas "Semana que vem (projeção)" de até 160 caracteres, e (FASE 2) linhas [{tipo, texto, perda, pergunta_id, acao_ids, modo}] de _agenda_linhas_do_fechamento. modo_leitura desligado: nada. O Secretário decide o que publica (sombra × ligado; vagas de REGRAS.maxManha). FASE 7 (7a P7, spec §5.7 item 3 e §7): com modo_vaga_fechamento fora de desligado, a saída ganha vagas_garantidas — com ligado, fechamento_vagas_agenda (+1 com alguma linha ligada de decisão de perda ≥ 80, a decisão crítica ou a compra urgente, até 2); em sombra, 0 — e vaga_teria (em sombra, as vagas que teria: o Secretário põe no detalhe); as linhas são lidas uma vez só. Desligado, a saída de antes, byte a byte. O Secretário soma vagas_garantidas às vagas que sobram de REGRAS.maxManha.';

-- agenda_ver (de 20261030100100_agenda_correcao_livre.sql)
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
  -- FASE 7: (7a P7) o foco gestor (spec §6.2: o que o gestor da agenda marcou ou marcaria sozinho e por quê, o que perguntou
  -- antes, o que fica de fora e como ele conta — _agenda_ver_gestor), antes da conferência dos 19 da Fase 6, que o foco gestor
  -- não alcança (o foco que não existe continua com a mensagem dos 19). Com login, só administrador e financeiro (42501, antes
  -- de ler a config); desligada a leitura, a frase de sempre.
  if v_foco = 'gestor' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if auth.uid() is not null and not public.is_admin_or_financial(auth.uid()) then
      raise exception 'O gestor da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    return public._agenda_ver_gestor(p_hoje) || jsonb_build_object('rota', 'gestor');
  end if;
  -- FASE 7: fim
  -- FASE 6: (P8) o foco aprendizado (spec-fase6 §5.8 e §6.2: o que a agenda aprendeu com o que aconteceu,
  -- _agenda_ver_aprendizado) e a conferência do foco com os 19 — antes da conferência dos 18 da Fase 5, que o foco
  -- aprendizado não alcança. Com login, só administrador e financeiro (42501, antes de ler a config); desligada a leitura, a
  -- frase de sempre.
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores', 'clientes', 'aprendizado') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras, fornecedores, clientes ou aprendizado)', p_foco
      using errcode = '22023';
  end if;
  if v_foco = 'aprendizado' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if auth.uid() is not null and not public.is_admin_or_financial(auth.uid()) then
      raise exception 'O que a agenda aprendeu é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    return public._agenda_ver_aprendizado(p_hoje) || jsonb_build_object('rota', 'aprendizado');
  end if;
  -- FASE 6: fim
  -- FASE 5: o foco clientes (a mensagem ao cliente: _agenda_ver_clientes, com ou sem a OS; a OS concluída também) e a
  -- conferência do foco com os 18 — antes da conferência dos 17 da Fase 4, que o foco clientes não alcança.
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores', 'clientes') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras, fornecedores ou clientes)', p_foco
      using errcode = '22023';
  end if;
  if v_foco = 'clientes' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    if nullif(btrim(p_os), '') is not null then
      v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
      if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
        return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                  'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                  'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
      end if;
      return public._agenda_ver_clientes((v_ro ->> 'id')::uuid, p_hoje) || jsonb_build_object('rota', 'clientes_os');
    end if;
    return public._agenda_ver_clientes(null, p_hoje) || jsonb_build_object('rota', 'clientes');
  end if;
  -- FASE 5: fim
  -- FASE 2: os focos decisoes, mudancas e plano
  -- FASE 3: os focos ppc, diarias, marcos, comissao e equipe
  -- FASE 4: os focos compras e fornecedores (a conferência e a mensagem com os 17)
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras ou fornecedores)', p_foco
      using errcode = '22023';
  end if;
  -- FASE 4: fim
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
    -- FASE 4: as compras e a espera de peça da OS (também fora da carteira: a concluída nos últimos 180 dias); os
    -- fornecedores não são de uma OS
    elsif v_foco = 'compras' then
      v_rota := 'compras_os';
      v_r := public._agenda_ver_compras((v_ro ->> 'id')::uuid, p_hoje);
    elsif v_foco = 'fornecedores' then
      v_rota := 'fornecedores';
      v_r := public._agenda_ver_fornecedores(p_hoje);
    -- FASE 4: fim
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
  -- FASE 4: o que comprar e até quando, as notas, o tempo até comprar e a pergunta ao fornecedor; como conto o prazo de
  -- cada fornecedor
  elsif v_foco = 'compras' then
    v_rota := 'compras';
    v_r := public._agenda_ver_compras(null, p_hoje);
  elsif v_foco = 'fornecedores' then
    v_rota := 'fornecedores';
    v_r := public._agenda_ver_fornecedores(p_hoje);
  -- FASE 4: fim
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
    -- CORREÇÃO 29/10 (P2): com a agenda automática ligada, o livre é UMA resposta, a do plano (quem ainda pega serviço em cada
    -- uma das próximas semanas, pelo marcado, pelo reservado e pelo teto de cada pessoa; o que ocupa a equipe; o que não ocupa
    -- ninguém até destravar), no lugar da fila em faixa da Fase 1 ("Livre ela não está: … de 3 a 6 semanas", que conta a OS
    -- travada como se ocupasse a equipe) seguida da frase da simulação ("a equipe já está livre")
    if v_lv ->> 'fonte' = 'simulacao' and nullif(v_lv ->> 'texto_completo', '') is not null then
      v_r := jsonb_set(v_r, '{texto}', to_jsonb(v_lv ->> 'texto_completo'));
    end if;
    -- CORREÇÃO 29/10 (P2): fim
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
    -- CORREÇÃO 29/10 (P2): com a agenda automática ligada, a linha do livre (a do plano) vai logo depois do marcado, no lugar
    -- da fila em faixa da Fase 1 (o resumo "Livre ela não está: … de 3 a 6 semanas", que contradizia o livre), e a linha do
    -- livre lá de baixo sai: a semana diz o livre uma vez só
    if (public._agenda_cfg()).modo_proposta = 'ligado' and nullif(v_r #>> '{dados,textos,resumo}', '') is not null
       and position((v_r #>> '{dados,textos,resumo}') in (v_r ->> 'texto')) > 0 then
      v_lv := coalesce(v_lv, public.agenda_livre_de_verdade(p_hoje, v_agora));
      if v_lv ->> 'fonte' = 'simulacao' then
        v_r := jsonb_set(v_r, '{texto}', to_jsonb(replace(replace(v_r ->> 'texto', E'\n' || (v_lv ->> 'texto'), ''),
                                                          v_r #>> '{dados,textos,resumo}', v_lv ->> 'texto')));
        v_r := jsonb_set(v_r, '{dados,livre_de_verdade}', v_lv);
      end if;
    end if;
    -- CORREÇÃO 29/10 (P2): fim
  end if;

  return v_r || jsonb_build_object('rota', v_rota);
end;
$function$;

comment on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5; Fase 3, P6; Fase 4, P6; Fase 5, P5): o despacho ÚNICO da ferramenta agenda_ver e dos comandos sem IA. os + simular_aprovacao → agenda_ctp; FASE 3: os + foco marcos → os 4 marcos (agenda_marcos_da_os, também fora da carteira); foco marcos sem os → pede a OS; FASE 4: os + foco compras → a espera de peça e o material da OS (_agenda_ver_compras, também fora da carteira); foco compras → o que comprar e até quando, as notas sem serviço dito, o tempo até comprar, a pergunta ao fornecedor e o detector em teste (_agenda_ver_compras); foco fornecedores → como conto o prazo de cada fornecedor (_agenda_ver_fornecedores; com ou sem os); os + foco material → agenda_ver_material; os → a visão da OS; simular {dias, com_quem, dono} → agenda_simular; FASE 2: foco decisoes → as decisões numeradas (agenda_decisoes_abertas; FASE 3: a da diária com as opções e as palavras) e o que mais a agenda quer saber; mudancas → o que mudou sozinho desde ontem com *desfaz*; plano → o publicado do período dia a dia (sombra: "Em teste"); FASE 3: ppc → agenda_ppc da semana do período; diarias → as diárias que a agenda lançou e as perguntas abertas; comissao → comissao_resumo_do_mes do mês dito em periodo ("outubro", "mês passado"; só a conta, nada é pago); equipe → o que a equipe respondeu hoje e no próximo dia útil; foco o_que_fazer → agenda_o_que_fazer (pessoa que não é o dono: o dia dela); atrasos/riscos → agenda_atrasos; material → agenda_ver_material(null); livre → resumo + livre de agenda_semana (FASE 3: com modo_proposta ligado, o livre de verdade pela simulação do motor, agenda_livre_de_verdade); aprontar → agenda_aprontar; pessoa (não o dono) + 1 dia → agenda_dia_da_pessoa; hoje/amanhã → o dia + o bloco 2 resumido; resto → agenda_semana (em ''ligado'' o marcado é o plano; FASE 3: e a frase do livre é a da simulação). periodo: hoje, amanha, semana, proxima_semana ou o que o dono disse. Referência que não existe (OS, pessoa, data, mês) → {ok:false, texto:"Não encontrei …"/a pergunta}; FASE 5: foco clientes (com ou sem os; a OS concluída também) → as mensagens ao cliente (_agenda_ver_clientes); foco fora da lista (os 18) lança 22023. Devolve {ok, texto, dados, rota}. FASE 6 (P8): foco aprendizado → o que a agenda aprendeu com o que aconteceu (_agenda_ver_aprendizado: o fator por tipo de OS, a presença do dono, os fornecedores, a capacidade do dono, o R$ por diária, o cliente e a revisão da carga, com o n de cada um, e as medidas); com login, só administrador e financeiro (42501). A lista dos focos passa a 19. CORREÇÃO 29/10 (P2): com a agenda automática ligada, o foco livre é UMA resposta, a do plano (agenda_livre_de_verdade.texto_completo: quem ainda pega serviço em cada uma das 3 semanas, pelo marcado, pelo reservado e pelo teto de cada pessoa; o que ocupa a equipe; o que não ocupa ninguém até destravar), sem a fila em faixa da Fase 1; na semana, a linha do livre (agenda_livre_de_verdade.texto) vai logo depois do marcado, no lugar da fila em faixa, e a linha do livre lá de baixo sai; simular (agenda_simular) em ligado é o encaixe do motor. Fora de ligado, tudo como antes. FASE 7 (7a P7, spec §6.2): foco gestor → o que o gestor da agenda marcou (ligado) ou marcaria (em teste) e por quê, o que perguntou antes de marcar, o que fica de fora, as compras da semana, os orçamentos que caberiam e como ele conta (_agenda_ver_gestor); com login, só administrador e financeiro (42501); desligada a leitura, a frase de sempre. A lista dos focos passa a 20.';

-- agenda_desfazer (de 20261029100600_agenda_fase6_rodada.sql)
create or replace function public.agenda_desfazer(p_acao uuid, p_autor uuid default null, p_via text default 'dono',
                                                  p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_a     public.agenda_acoes%rowtype;
  v_nome  text;
  v_x     record;
  v_novas uuid[] := '{}';
  v_canc  uuid[] := '{}';
  v_id    uuid;
  v_os    uuid;
  v_acao  uuid;
  v_txt   text;
  v_q     public.agenda_perguntas%rowtype;
  v_dias  date[];
  -- FASE 7: (7a P7) os ramos das ações do gestor (estimar, dupla, gestor) e quem saiu da equipe
  v_f7_pl    public.os_planejamento%rowtype;
  v_f7_txt   text;
  v_f7_acao  uuid;
  v_f7_sai   uuid[] := '{}';
  v_f7_fora  uuid[] := '{}';
  v_f7_ficam int := 0;
  v_f7_nomes text;
  -- FASE 7: fim
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found then
    raise exception 'Não encontrei essa mudança.' using errcode = 'P0002';
  end if;
  v_os := v_a.service_order_id;
  v_nome := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                        join public.clients cl on cl.id = so.client_id where so.id = v_os), 'serviço');
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste da agenda automática: nada mudou para desfazer.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.tipo = 'desfazer' then
    return jsonb_build_object('ok', false, 'texto', 'Não desfaço um desfazer: me diga o dia que você quer.');
  end if;
  -- FASE 3: a conclusão e a entrega têm o desfazer delas (o status e a saída pela porta, as cobranças da conclusão, a
  -- comissão de vendedor, os vencimentos "na entrega" e a entrega): _agenda_desfazer_marco (20261026100100).
  if v_a.tipo in ('concluir', 'entregar') then
    return public._agenda_desfazer_marco(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 3 (P4): a diária que a agenda lançou: apaga o turno que ela criou, se o acerto está aberto (_agenda_desfazer_diaria).
  if v_a.tipo = 'diaria' then
    return public._agenda_desfazer_diaria(v_a.id, p_autor, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 4: a mudança do material que o gestor fez sozinho (a previsão pela mensagem do fornecedor, a chegada pela nota
  -- importada): as linhas voltam como estavam, se ninguém mexeu nelas depois (_agenda_desfazer_material, 20261027100400).
  if v_a.tipo = 'material' then
    return public._agenda_desfazer_material(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 4: fim
  -- FASE 5: o que a resposta do cliente mudou (a confirmação, o pedido de dia, o acesso: a ação com depois.resposta_id) tem
  -- o desfazer dela (_agenda_desfazer_cliente, 20261028100400); a mensagem enviada não se desmanda; o acorde e a decisão do
  -- aviso crítico não mudaram nada na agenda.
  if v_a.origem = 'cliente' and v_a.tipo in ('fixar', 'cliente') and v_a.depois ? 'resposta_id' then
    return public._agenda_desfazer_cliente(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  if v_a.tipo = 'cliente' then
    return jsonb_build_object('ok', false,
      'texto', case when v_a.depois ? 'mensagem_id' then 'Mensagem enviada não se desmanda.'
                    else 'Isso foi um aviso para você: nada mudou na agenda para desfazer.' end);
  end if;
  -- FASE 5: fim
  -- FASE 6: (P6) o que o aprendizado mudou (a troca que entrou sozinha e a decisão 1 ou 3 do dono) tem o desfazer dele: o
  -- valor de antes volta e a chave fica travada; a carga volta carga_max (_agenda_desfazer_aprendizado, 20261029100600).
  if v_a.tipo = 'aprendizado' then
    return public._agenda_desfazer_aprendizado(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 6: fim
  -- FASE 7: (7a P7, spec R3 e §5.7) as ações do gestor que não são de alocação têm o ramo delas: estimar (os dias que o gestor
  -- gravou pelo prazo ou pela opção 1: os_planejamento.dias, estimativa_fonte e estimativa_em voltam ao antes da ação), dupla
  -- (dupla_dita, dupla_meios, dupla_motivo e dupla_em voltam) e gestor (*gestor, só propor* / *pode marcar*: gestor_so_propor e
  -- gestor_so_propor_em voltam). Só se nada mudou depois da ação (o que está gravado é o depois dela); senão a recusa diz o que
  -- mudou. reparar e reestimar são de alocação e seguem o caminho de sempre.
  if v_a.tipo in ('estimar', 'dupla', 'gestor') then
    if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
      return jsonb_build_object('ok', false,
        'texto', case when v_a.tipo = 'gestor' then 'Não dá mais para desfazer: passou o prazo. Diga *gestor, só propor* ou *gestor, pode marcar*.'
                      else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga.', v_nome) end);
    end if;
    if v_a.tipo = 'gestor' then
      if (select c.gestor_so_propor from public.agenda_config c where c.id)
         is distinct from (v_a.depois ->> 'gestor_so_propor')::boolean then
        return jsonb_build_object('ok', false,
          'texto', 'Não desfaço: depois disso você já mudou o gestor de novo. Diga *gestor, só propor* ou *gestor, pode marcar*.');
      end if;
      update public.agenda_config
         set gestor_so_propor = coalesce((v_a.antes ->> 'gestor_so_propor')::boolean, false),
             gestor_so_propor_em = (v_a.antes ->> 'gestor_so_propor_em')::timestamptz,
             atualizado_em = p_agora, atualizado_por = p_autor
       where id;
      v_f7_txt := case when coalesce((v_a.antes ->> 'gestor_so_propor')::boolean, false)
                       then 'Desfeito: voltei a só sugerir. *gestor, pode marcar* volta a marcar.'
                       else 'Desfeito: voltei a marcar sozinho; o que eu marcar vem no seu fechamento, com *desfaz*.' end;
    else
      select * into v_f7_pl from public.os_planejamento where service_order_id = v_os for update;
      if not found then
        return jsonb_build_object('ok', false, 'texto', format('Não achei o planejamento do %s: nada mudou.', v_nome));
      end if;
      if v_a.tipo = 'estimar' then
        if v_f7_pl.dias is distinct from (v_a.depois ->> 'dias')::numeric or v_f7_pl.estimativa_fonte is distinct from 'orcamento' then
          return jsonb_build_object('ok', false,
            'texto', format('Não desfaço: depois disso os dias do %s mudaram (%s). Para mudar de novo, me diga os dias.', v_nome,
                            coalesce(public._agenda_dias(v_f7_pl.dias), 'sem dias')));
        end if;
        update public.os_planejamento
           set dias = (v_a.antes ->> 'dias')::numeric, estimativa_fonte = v_a.antes ->> 'estimativa_fonte',
               estimativa_em = (v_a.antes ->> 'estimativa_em')::timestamptz,
               historico = public._os_material_historico(v_f7_pl.historico, jsonb_build_object(
                 'em', p_hoje, 'quando', p_agora, 'autor', p_autor, 'por', 'dono', 'motivo', 'desfeito', 'acao', v_a.id,
                 'antes', v_a.depois, 'depois', v_a.antes)),
               atualizado_em = p_agora, atualizado_por = p_autor
         where service_order_id = v_os;
        v_f7_txt := case when v_a.antes ->> 'dias' is null
                         then format('Desfeito: o %s volta sem os dias que eu contei (%s). Me diga quantos dias são.',
                                     public._agenda_rotulo_da_os(v_os), public._agenda_dias((v_a.depois ->> 'dias')::numeric))
                         else format('Desfeito: o %s volta a %s, como estava.', public._agenda_rotulo_da_os(v_os),
                                     public._agenda_dias((v_a.antes ->> 'dias')::numeric)) end;
      else
        if v_f7_pl.dupla_dita is distinct from v_a.depois ->> 'dupla_dita'
           or v_f7_pl.dupla_meios is distinct from (v_a.depois ->> 'dupla_meios')::smallint then
          return jsonb_build_object('ok', false,
            'texto', format('Não desfaço: depois disso a dupla do %s mudou. Diga *%s com dupla* ou *%s sem dupla*.', v_nome, v_nome, v_nome));
        end if;
        update public.os_planejamento
           set dupla_dita = v_a.antes ->> 'dupla_dita', dupla_meios = (v_a.antes ->> 'dupla_meios')::smallint,
               dupla_motivo = v_a.antes ->> 'dupla_motivo', dupla_em = (v_a.antes ->> 'dupla_em')::timestamptz,
               historico = public._os_material_historico(v_f7_pl.historico, jsonb_build_object(
                 'em', p_agora, 'autor', p_autor, 'por', 'dono', 'trecho', 'desfeito', 'acao', v_a.id,
                 'antes', v_a.depois, 'depois', v_a.antes)),
               atualizado_em = p_agora, atualizado_por = p_autor
         where service_order_id = v_os;
        v_f7_txt := format('Desfeito: o %s volta %s.', public._agenda_rotulo_da_os(v_os),
                           case v_a.antes ->> 'dupla_dita'
                             when 'todos' then 'com dupla'
                             when 'nao' then 'sem dupla'
                             when 'inicio' then 'com dupla no início'
                             when 'fim' then 'com dupla no fim'
                             else 'ao normal: 1 pessoa, e dupla só quando você marcar' end);
      end if;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto,
                                     autor, desfaz_a)
    values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
            v_a.os_ids, false, jsonb_build_object('acao', v_a.id), v_a.antes, left(v_f7_txt, 400), p_autor, v_a.id)
    returning id into v_f7_acao;
    update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_f7_acao where id = v_a.id;
    return jsonb_build_object('ok', true, 'texto', v_f7_txt, 'acao_id', v_f7_acao, 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb);
  end if;
  -- FASE 7: fim
  if v_a.desfazivel_ate is null then
    return jsonb_build_object('ok', false, 'texto', 'Essa mudança foi pedida por você: para mudar de novo, me diga o dia.');
  end if;
  if p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false,
      'texto', case when exists (select 1 from public.agenda_alocacoes a where a.id = any (v_a.alocacoes_criadas)
                                                                       and lower(a.periodo) <= p_agora)
                    then format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome)
                    else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga o dia.', v_nome) end);
  end if;
  if exists (select 1 from public.agenda_alocacoes a
              where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')
                and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome));
  end if;
  -- recriar o que saiu não pode bater em quem já está no lugar
  select a.dia, a.turno, py.name as pessoa, cl.name as cliente into v_x
    from public.agenda_alocacoes c
    join public.agenda_alocacoes a on a.payee_id = c.payee_id and a.periodo && c.periodo and a.estado in ('publicada', 'fixada')
                                  and not (a.id = any (v_a.alocacoes_criadas))
    join public.payees py on py.id = a.payee_id
    join public.service_orders so on so.id = a.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
   order by a.dia, a.turno = 'tarde'
   limit 1;
  if found then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: o %s já está no %s %s.', public._agenda_nome_curto(v_x.pessoa),
                      coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), public._agenda_meio_texto(v_x.dia, v_x.turno)));
  end if;

  -- FASE 7: (7a P7; fase7-padroes "medição de 30/10", item 4) o que a ação tirou e era de quem não está mais na equipe (a
  -- grade, agenda_capacidade, naquele dia) não volta: o *desfaz* restaura só o que cabe e diz o resto. Se tudo o que voltaria é
  -- de quem saiu e a ação não criou nada que ainda esteja de pé, nada muda (a recusa diz por quê): voltar o Lenine com João e
  -- Roberto, que saíram, faria a vigia remanejar de novo e mandar outro aviso com outro *desfaz*.
  select coalesce(array_agg(c.id) filter (where not g.na_grade), '{}'), coalesce(array_agg(distinct c.payee_id) filter (where not g.na_grade), '{}'),
         count(*) filter (where g.na_grade)
    into v_f7_sai, v_f7_fora, v_f7_ficam
    from public.agenda_alocacoes c
    cross join lateral (select exists (select 1 from public.agenda_capacidade(c.dia, c.dia, p_hoje) k
                                        where k.payee_id = c.payee_id) as na_grade) g
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora;
  if cardinality(v_f7_fora) > 0 then
    v_f7_nomes := public._agenda_lista(array(select public._agenda_nome_curto(py.name) from public.payees py
                                              where py.id = any (v_f7_fora) order by py.name, py.id), null);
  end if;
  if cardinality(v_f7_fora) > 0 and v_f7_ficam = 0
     and not exists (select 1 from public.agenda_alocacoes a
                      where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')) then
    return jsonb_build_object('ok', false, 'status', 'saiu_da_equipe',
      'texto', format('Não dá para desfazer como estava: %s não %s mais na equipe, e era com %s que o %s estava. Nada mudou; ele volta à agenda com a equipe de agora.',
                      v_f7_nomes, case when cardinality(v_f7_fora) = 1 then 'está' else 'estão' end,
                      case when cardinality(v_f7_fora) = 1 then 'ele' else 'eles' end, v_nome));
  end if;
  -- FASE 7: fim
  -- 1. O que a ação criou sai.
  for v_id in select a.id from public.agenda_alocacoes a
               where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada') order by a.dia, a.turno, a.id loop
    if (select estado from public.agenda_alocacoes where id = v_id) = 'fixada' then
      perform set_config('agenda.mexe_fixado', 'on', true);
    end if;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = v_id;
    perform set_config('agenda.mexe_fixado', 'off', true);
    v_canc := v_canc || v_id;
  end loop;
  -- 2. O que ela tirou volta, igual (mesma pessoa, dia, turno e presença), do que ainda não começou.
  for v_x in select c.* from public.agenda_alocacoes c
              where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
              order by c.dia, c.turno = 'tarde', c.payee_id, c.id loop
    -- FASE 7: (7a P7) o meio-dia de quem saiu da equipe não volta
    continue when v_x.id = any (v_f7_sai);
    -- FASE 7: fim
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id,
                                         fixado_por, reserva_de, condicao, condicao_tipo, condicao_ate, motivos)
    values (v_x.service_order_id, v_x.payee_id, v_x.dia, v_x.turno, v_x.presenca, v_x.tipo,
            case when v_x.fixado_por is not null then 'fixada' else 'publicada' end, v_x.origem, v_x.id,
            v_x.fixado_por, v_x.reserva_de, v_x.condicao, v_x.condicao_tipo, v_x.condicao_ate, v_x.motivos)
    returning id into v_id;
    v_novas := v_novas || v_id;
  end loop;
  -- 3. O status volta pela porta (a regra de não regredir o que começou continua valendo) e o espelho acompanha.
  if v_a.tipo = 'status' and v_a.status_antes is not null and v_os is not null then
    perform public.os_transicionar_status(v_os, v_a.status_antes, 'desfazer', null, p_autor, null, p_hoje, p_agora);
  elsif v_os is not null then
    if public._agenda_os_tem_dia(v_os, p_hoje) then
      if (select status from public.service_orders where id = v_os) in ('open', 'approved', 'awaiting_parts') then
        perform public.os_transicionar_status(v_os, 'scheduled', 'desfazer', null, p_autor, null, p_hoje, p_agora);
      end if;
    elsif (select status from public.service_orders where id = v_os) = 'scheduled' then
      perform public.os_transicionar_status(v_os, case when v_a.status_antes in ('open', 'approved', 'awaiting_parts')
                                                       then v_a.status_antes else 'approved' end,
                                            'desfazer', null, p_autor, null, p_hoje, p_agora);
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
  end if;

  v_dias := array(select a.dia from public.agenda_alocacoes a where a.id = any (v_novas) and a.tipo <> 'reserva');
  v_txt := case when cardinality(v_dias) > 0
                then format('Desfeito: o %s volta para %s, como estava.', public._agenda_rotulo_da_os(v_os), public._agenda_dias_texto(v_dias))
                when cardinality(v_novas) > 0 then format('Desfeito: a reserva do %s volta como estava.', public._agenda_rotulo_da_os(v_os))
                else format('Desfeito: o %s sai da agenda, como estava.', coalesce(public._agenda_rotulo_da_os(v_os), 'serviço')) end;
  -- FASE 7: (7a P7) e diz o que não voltou
  if cardinality(v_f7_fora) > 0 then
    v_txt := v_txt || format(' %s não %s mais na equipe: os dias %s não voltam.', v_f7_nomes,
                             case when cardinality(v_f7_fora) = 1 then 'está' else 'estão' end,
                             case when cardinality(v_f7_fora) = 1 then 'dele' else 'deles' end);
  end if;
  -- FASE 7: fim
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, critica,
                                   versao_depois, alocacoes_criadas, alocacoes_canceladas, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
          v_a.os_ids, v_a.proposta_id, false, (public._agenda_cfg()).versao_plano, v_novas, v_canc,
          jsonb_build_object('acao', v_a.id), jsonb_build_object('alocacoes', to_jsonb(v_novas)), left(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_alocacoes set acao_id = v_acao where id = any (v_novas);
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;

  -- Desfazer uma decisão crítica não a reabre: a decisão volta ao dono como pergunta nova, do mesmo tipo.
  if v_a.critica and v_a.pergunta_id is not null then
    select * into v_q from public.agenda_perguntas where id = v_a.pergunta_id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao,
                                         recomendacao_texto, versao_base, modo, criada_em)
    values (v_q.tipo, left(v_q.chave || ':refeita:' || left(v_acao::text, 8), 200), v_q.service_order_id, v_q.os_ids, v_q.perda_em,
            v_q.texto, v_q.opcoes, v_q.recomendacao, v_q.recomendacao_texto, (public._agenda_cfg()).versao_plano, v_q.modo, p_agora)
    on conflict (chave, modo) where estado = 'aberta' do nothing;
    v_txt := format('Desfeito. A decisão sobre o %s volta a ficar com você.', v_nome);
  end if;
  -- FASE 3: o replano que a ausência da equipe causou ("não vou" ou o silêncio até as 9h): desfazer também tira a ausência
  -- daquele dia (senão a vigia replanejaria de novo no tique seguinte). "Se ele estiver lá, *desfaz Vanderlei*."
  update public.agenda_disponibilidade d set substituida_em = p_agora
   where d.substituida_em is null
     and d.id in (select (e.depois ->> 'disponibilidade')::uuid from public.agenda_acoes e
                   where e.tipo = 'equipe' and e.depois ->> 'disponibilidade' is not null
                     and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text);
  -- FASE 3: fim
  -- FASE 5: o replano que o pedido de dia do cliente causou, desfeito direto (sem a ação do cliente): o pedido sai junto (o
  -- bem indisponível e o "não antes de" voltam; senão a vigia replanejaria de novo no tique seguinte) e a ação do cliente
  -- fica desfeita. Quem desfaz pela ação do cliente (_agenda_desfazer_cliente) liga agenda.desfazer_cliente e faz isso ela.
  if coalesce(current_setting('agenda.desfazer_cliente', true), '') <> 'on' then
    for v_x in select e.id from public.agenda_acoes e
                where e.tipo = 'cliente' and e.origem = 'cliente' and e.executada and e.desfeita_em is null
                  and e.depois ->> 'efeito' = 'replanejou'
                  and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text loop
      perform public._agenda_cliente_restaurar_pedido(v_x.id, p_agora);
      update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_x.id;
    end loop;
  end if;
  -- FASE 5: fim
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você."). Fase 3: concluir e entregar vão a _agenda_desfazer_marco (as cobranças da conclusão, a saída, a comissão de vendedor e a entrega); a diária da agenda a _agenda_desfazer_diaria (apaga o turno que ela criou, com o acerto aberto); desfazer o replano da ausência da equipe tira a ausência do dia (agenda_disponibilidade substituída). Fase 4 (P4): a ação material (a previsão pela mensagem do fornecedor, a chegada pela nota) vai a _agenda_desfazer_material (as linhas voltam se ninguém mexeu nelas depois). Fase 5 (P4): o que a resposta do cliente mudou (a ação fixar/cliente de origem cliente com depois.resposta_id: a confirmação, o pedido de dia, o acesso) vai a _agenda_desfazer_cliente; a outra ação cliente (a mensagem enviada, o acorde, a decisão do aviso) não se desfaz ("Mensagem enviada não se desmanda."); desfazer direto o replano que o pedido de dia causou também tira o pedido (_agenda_cliente_restaurar_pedido) e deixa a ação do cliente desfeita. Fase 6 (P6): a ação aprendizado vai a _agenda_desfazer_aprendizado (o em_uso de antes volta, nulo = o padrão, e a chave fica travada por aprender_trava_dias; a da carga volta carga_max). FASE 7 (7a P7, spec R3): as ações do gestor que não são de alocação têm o ramo delas — estimar (os_planejamento.dias, estimativa_fonte e estimativa_em voltam ao antes da ação: "Desfeito: o Nelson (OS-00112) volta sem os dias que eu contei (4 dias). Me diga quantos dias são."), dupla (dupla_dita, dupla_meios, dupla_motivo e dupla_em voltam) e gestor (gestor_so_propor e gestor_so_propor_em voltam), cada uma só se nada mudou depois dela (senão a recusa diz o que mudou), dentro do desfazivel_ate; reparar e reestimar seguem o caminho de alocação de sempre. E (a medição de 30/10, item 4) o que a ação tirou e era de quem não está mais na equipe naquele dia (agenda_capacidade) não volta: o desfazer restaura só o que cabe e diz o resto ("… João e Roberto não estão mais na equipe: os dias deles não voltam."); se tudo o que voltaria é de quem saiu e a ação não criou nada de pé, nada muda ({ok: false, status saiu_da_equipe}).';

-- _agenda_ver_plano (de 20261030100000_agenda_correcao_leituras.sql)
create or replace function public._agenda_ver_plano(p_de date, p_ate date, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_de   date := coalesce(p_de, p_hoje);
  v_ate  date := coalesce(p_ate, p_hoje - (extract(isodow from p_hoje)::int - 1) + 12);
  v_l    text[] := '{}';
  v_d    date;
  v_lin  jsonb;
  v_n    int := 0;
  v_ab   jsonb;
  p      record;
  v_fer  text;
  -- CORREÇÃO 29/10 (P1): as reservas que já disseram a condição e o dia da continuação do bloco
  v_vistas uuid[] := '{}';
  v_dc     date;
  -- CORREÇÃO 29/10 (P1): fim
begin
  if v_ate < v_de then
    raise exception 'agenda_ver: período invertido (% a %)', v_de, v_ate using errcode = '22023';
  end if;
  if cf.modo_proposta = 'ligado' then
    v_d := v_de;
    while v_d <= v_ate loop
      v_lin := public.agenda_linhas_do_dia(v_d, null, p_hoje);
      -- CORREÇÃO 29/10 (P1): a reserva diz quem vai e que é reserva ("Lenine (OS-00074): João o dia todo, Roberto o dia todo
      -- — reservado, se …"); a condição só na 1ª vez em que a OS aparece, depois "(mesma condição)"
      v_lin := public._agenda_plano_reservas(v_lin, v_d, v_vistas);
      -- FASE 7: (7a P7) o dia marcado pela estimativa do gestor (duracao_fonte orcamento) diz "(estimativa minha)" depois das pessoas
      v_lin := public._agenda_plano_estimativa(v_lin, v_d);
      -- FASE 7: fim
      v_vistas := v_vistas || array(select (x ->> 'os')::uuid from jsonb_array_elements(v_lin) x
                                     where coalesce((x ->> 'reserva')::boolean, false));
      -- CORREÇÃO 29/10 (P1): fim
      v_fer := public.agenda_feriado(v_d);
      if jsonb_array_length(v_lin) > 0 then
        v_n := v_n + jsonb_array_length(v_lin);
        v_l := v_l || (public._agenda_dia_rotulo(v_d, p_hoje) || ': '
                       || (select string_agg((x ->> 'hora') || ' ' || (x ->> 'texto'), '; ' order by o)
                             from jsonb_array_elements(v_lin) with ordinality t(x, o)) || '.');
      elsif v_fer is not null and extract(isodow from v_d) between 1 and 5 then
        v_l := v_l || (public._agenda_dia_rotulo(v_d, p_hoje) || ': ' || v_fer || '.');
      end if;
      v_d := v_d + 1;
    end loop;
    -- CORREÇÃO 29/10 (P1): o bloco que tem dia no período e passa do fim dele aparece inteiro, só com as OS dele ("Ter 10/11
    -- (continua): 08:00 Lenine (OS-00074): … — reservado (mesma condição).")
    for v_dc in select distinct v.dia from public.v_agenda_dia v
                 where v.dia > v_ate
                   and v.service_order_id in (select w.service_order_id from public.v_agenda_dia w where w.dia between v_de and v_ate)
                 order by 1 loop
      v_lin := coalesce((select jsonb_agg(x order by o)
                           from jsonb_array_elements(public.agenda_linhas_do_dia(v_dc, null, p_hoje)) with ordinality t(x, o)
                          where (x ->> 'os')::uuid in (select w.service_order_id from public.v_agenda_dia w
                                                        where w.dia between v_de and v_ate)), '[]'::jsonb);
      v_lin := public._agenda_plano_reservas(v_lin, v_dc, v_vistas);
      -- FASE 7: (7a P7) também na continuação do bloco
      v_lin := public._agenda_plano_estimativa(v_lin, v_dc);
      -- FASE 7: fim
      v_vistas := v_vistas || array(select (x ->> 'os')::uuid from jsonb_array_elements(v_lin) x
                                     where coalesce((x ->> 'reserva')::boolean, false));
      if jsonb_array_length(v_lin) > 0 then
        v_l := v_l || (public._agenda_dia_rotulo(v_dc, p_hoje) || ' (continua): '
                       || (select string_agg((x ->> 'hora') || ' ' || (x ->> 'texto'), '; ' order by o)
                             from jsonb_array_elements(v_lin) with ordinality t(x, o)) || '.');
      end if;
    end loop;
    -- CORREÇÃO 29/10 (P1): fim
    v_l := array[public._agenda_periodo_rotulo(v_de, v_ate, p_hoje)
                 || case when v_n = 0 then ': nada publicado na agenda.' else ', o que está publicado:' end] || v_l;
    v_ab := public.agenda_propostas_abertas(p_agora);
    if jsonb_array_length(v_ab) > 0 then
      v_l := v_l || ('Montei e ainda não publiquei: '
                     || (select string_agg(format('%s) %s', x ->> 'n', coalesce(x ->> 'titulo', 'uma mudança')), '; ' order by (x ->> 'n')::int)
                           from jsonb_array_elements(v_ab) x)
                     || '. Para publicar, diga "publica a 1".');
    end if;
  elsif cf.modo_proposta = 'sombra' then
    select pr.* into p from public.agenda_propostas pr
     where pr.modo = 'sombra' and pr.escopo = 'semana'
     order by pr.criada_em desc, pr.id desc limit 1;
    if p.id is null then
      v_l := array['Em teste: ainda não montei nenhuma semana.'];
    else
      v_l := array['Em teste (nada foi publicado): eu montaria assim — ' || coalesce(p.textos ->> 'titulo', 'a semana') || '.']
             || array(select x from jsonb_array_elements_text(coalesce(p.textos -> 'linhas', '[]'::jsonb)) with ordinality t(x, o) order by o)
             || array(select 'Fora: ' || regexp_replace(x, '\?\.$', '?')
                        from jsonb_array_elements_text(coalesce(p.textos -> 'fora', '[]'::jsonb)) with ordinality t(x, o)
                       order by o);
    end if;
  else
    v_l := array['A agenda automática está desligada: não há plano publicado.'];
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('de', v_de, 'ate', v_ate, 'linhas', v_n,
                                                        'abertas', coalesce(v_ab, '[]'::jsonb)));
end;
$function$;

comment on function public._agenda_ver_plano(date, date, date, timestamptz) is
  'Agenda de Produção (Fase 2, P5): agenda_ver foco plano — em ligado, o publicado de [p_de, p_ate] dia a dia ("Ter 03/11: 08:00 Vanderlei (OS-00069), dia 1 de 3: você abre, Roberto o dia todo; 13:00 …"), o feriado de dia útil no meio, e as montadas e não publicadas numeradas por agenda_propostas_abertas ("publica a 1"); em sombra, a última semana montada pela sombra ("Em teste (nada foi publicado): eu montaria assim — …"); desligado diz que não há plano. Sem período: de hoje ao sábado da semana que vem. {ok, texto, dados}. CORREÇÃO 29/10 (P1): a reserva diz quem vai e que é reserva ("Qui 05/11: 08:00 Lenine (OS-00074): João o dia todo, Roberto o dia todo — reservado, se você disser até qua 04/11 se tem peça a comprar."; a condição só na 1ª vez, depois "(mesma condição)"; no pátio "reservado no pátio"; acima da carga "reservado (acima da carga)"), e o bloco que começou no período e passa do fim dele aparece inteiro, só com as OS dele ("Ter 10/11 (continua): 08:00 Lenine (OS-00074): … — reservado (mesma condição)."). FASE 7 (7a P7): o dia com alocação de compromisso de duracao_fonte orcamento (o gestor marcou pela estimativa do orçamento) diz "(estimativa minha)" depois das pessoas, também na continuação do bloco (_agenda_plano_estimativa). Sem alocação assim, a saída de antes, byte a byte.';

-- agenda_saude (de 20261029100950_agenda_fase6_correcao_textos.sql)
create or replace function public.agenda_saude(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_cart    uuid[];
  v_ult     record;
  v_vig     jsonb;
  v_hoje    jsonb;
  v_crit    jsonb;
  v_perg    jsonb;
  v_prop    jsonb;
  v_plano   jsonb;
  v_inv     jsonb;
  v_fech    jsonb;
  v_sem     int;
  v_regra   jsonb;
  v_leu     boolean;
  v_choques int;
  -- FASE 3
  v_rot     jsonb;
  v_eq      jsonb;
  v_dia     jsonb;
  v_conc    jsonb;
  v_marcos  jsonb;
  v_com     jsonb;
  v_teto    int;
  v_janela  int;
  v_semconf int;
  v_sobre   int;
  v_semrec  int;
  v_pay     int;
  -- FASE 4: o material e a mensagem ao fornecedor
  v_mrod    jsonb;
  v_rem     jsonb;
  v_mperg   jsonb;
  v_semdono int;
  v_semorig int;
  v_prec    jsonb;
  v_det     jsonb;
  v_fsombra int;
  v_ffora   int;
  v_fteto   int;
  v_fproib  int;
  v_forn    jsonb;
  v_cob     jsonb;
  v_med     numeric;
  v_zeros4  boolean;
  v_mat     jsonb;
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente
  v_crod    jsonb;
  v_cmsg    jsonb;
  v_caprov  jsonb;
  v_cjan    int;
  v_cdom    int;
  v_cteto   int;
  v_cint    int;
  v_cproib  int;
  v_csombra int;
  v_csemap  int;
  v_ccrit   int;
  v_cvesp   int;
  v_cdepois int;
  v_caudio  int;
  v_cmet    jsonb;
  v_zeros5  boolean;
  v_cli     jsonb;
  -- FASE 5: fim
  -- FASE 6: o aprendizado
  v_arod    record;
  v_apeq    int;
  v_afora   int;
  v_agrande int;
  v_aatras  int;
  v_asemcl  int;
  v_afat    int;
  v_amet    jsonb;
  v_zeros6  boolean;
  v_apr     jsonb;
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros de antes do aprendizado (para o ok sair com as janelas de agenda_config)
  v_z4_antes boolean;
  -- FASE 7: (7a P7) o gestor da agenda
  v_ges     jsonb;
  v_gz      jsonb;
  v_gzeros  boolean;
  v_gdesde  timestamptz;
  v_gmodos  jsonb;
  v_gult    record;
  v_gr      jsonb;
  -- FASE 7: fim
  -- CORREÇÃO FASE 6: fim
begin
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);

  select max(x.p_agora) as ultima, max(x.rodou_em) as rodou_em,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_ult from public.agenda_vigia_rodadas x
   -- FASE 3: a rotina da equipe grava na mesma tabela (rotina = 'rotina'); a vigia é só a dela.
   where x.rotina = 'vigia';
  v_vig := jsonb_build_object(
    'ultima_rodada', v_ult.ultima, 'rodou_em', v_ult.rodou_em,
    'rodou_nas_ultimas_2h', coalesce(v_ult.ultima > p_agora - interval '2 hours', false),
    'rodadas_24h', coalesce(v_ult.n24, 0), 'erros_ultima_rodada', coalesce(v_ult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'));

  select jsonb_build_object(
           'publicar', count(*) filter (where a.executada and a.tipo = 'publicar'),
           'criar', count(*) filter (where a.executada and a.tipo = 'criar'),
           'mover', count(*) filter (where a.executada and a.tipo = 'mover'),
           'cancelar', count(*) filter (where a.executada and a.tipo = 'cancelar'),
           'promover', count(*) filter (where a.executada and a.tipo = 'promover_reserva'),
           'soltar', count(*) filter (where a.executada and a.tipo = 'soltar_reserva'),
           'status', count(*) filter (where a.executada and a.tipo = 'status'),
           'resultado', count(*) filter (where a.executada and a.tipo = 'resultado'),
           'desfeitas', count(*) filter (where a.executada and a.tipo = 'desfazer'),
           'sombra', count(*) filter (where not a.executada))
    into v_hoje from public.agenda_acoes a where a.dia = p_hoje;

  -- A prova: nenhuma ação crítica executada sem a decisão registrada (o gatilho impede; isto confere).
  select count(*) into v_sem
    from public.agenda_acoes a left join public.agenda_perguntas q on q.id = a.pergunta_id
   where a.executada and a.critica and (q.id is null or q.estado <> 'respondida' or q.opcao_escolhida is null);
  -- E o erro de classificação: ação autônoma executada como não crítica que a regra diz crítica.
  select jsonb_build_object('n', count(*), 'acoes', coalesce(jsonb_agg(a.id order by a.criada_em, a.id), '[]'::jsonb)) into v_regra
    from public.agenda_acoes a
   where a.executada and not a.critica and a.origem in ('motor', 'vigia', 'conferencia')
     and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
     and public._agenda_criticidade_da_acao(a.id) is not null;
  v_crit := jsonb_build_object(
    'abertas', (select count(*) from public.agenda_perguntas q where q.critica and q.estado = 'aberta'),
    'respondidas_7d', (select count(*) from public.agenda_perguntas q
                        where q.critica and q.estado = 'respondida' and q.respondida_em > p_agora - interval '7 days'),
    'sem_decisao', v_sem, 'pela_regra_sem_decisao', (v_regra ->> 'n')::int, 'pela_regra_acoes', v_regra -> 'acoes');

  v_perg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q where q.estado = 'aberta' group by q.tipo) t), '{}'::jsonb),
    'abertas_sombra', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'sombra'),
    'mostradas_hoje', (select count(*) from public.agenda_perguntas q
                        where (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  select jsonb_build_object(
           'abertas', count(*) filter (where p.estado = 'aberta'),
           'obsoletas_7d', count(*) filter (where p.estado = 'obsoleta' and p.criada_em > p_agora - interval '7 days'),
           'aplicadas_7d', count(*) filter (where p.estado = 'aplicada' and p.criada_em > p_agora - interval '7 days'),
           'sombra_7d', count(*) filter (where p.modo = 'sombra' and p.criada_em > p_agora - interval '7 days'))
    into v_prop from public.agenda_propostas p;

  select jsonb_build_object(
           'alocacoes_vigentes_futuras', count(*) filter (where a.dia >= p_hoje and a.resultado is null),
           'os_programadas', count(distinct a.service_order_id) filter (where a.dia >= p_hoje and a.resultado is null and a.tipo <> 'reserva'),
           'reservas', count(*) filter (where a.dia >= p_hoje and a.tipo = 'reserva'),
           'sem_registro_7d', count(*) filter (where a.resultado = 'sem_registro' and a.dia > p_hoje - 7))
    into v_plano from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada');

  select count(*) into v_choques
    from public.agenda_alocacoes a join public.agenda_alocacoes b
      on b.payee_id = a.payee_id and b.id > a.id and b.periodo && a.periodo
   where a.estado in ('publicada', 'fixada') and b.estado in ('publicada', 'fixada');
  v_inv := jsonb_build_object(
    'vigente_de_os_fora_da_carteira', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                                        where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                                          and not (a.service_order_id = any (v_cart))),
    'espelho_divergente', case when cf.modo_proposta <> 'ligado' then 0 else (
       select count(*) from public.service_orders so
        cross join lateral (select min(lower(a.periodo)) as ini, max(upper(a.periodo)) as fim from public.agenda_alocacoes a
                             where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.resultado is distinct from 'nao_cumprido') m
        where so.id = any (v_cart)
          and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = so.id)
          and (so.scheduled_start_at is distinct from m.ini or so.scheduled_end_at is distinct from m.fim)) end,
    'choques', v_choques);

  if to_regclass('public.resumo_tarde') is not null then
    execute $q$select exists (select 1 from public.resumo_tarde t
                               where t.dia = $1 and jsonb_typeof(t.detalhe -> 'agenda') = 'object'
                                 and (t.detalhe -> 'agenda' ? 'linhas_diria' or t.detalhe -> 'agenda' ? 'linhas'))$q$
      into v_leu using p_hoje;
  end if;
  v_fech := jsonb_build_object(
    'leu_o_plano_hoje', v_leu,
    'linhas_mostradas', (select count(*) from public.agenda_acoes a
                          where a.contada_via = 'fechamento' and (a.contada_em at time zone 'America/Sao_Paulo')::date = p_hoje)
                        + (select count(*) from public.agenda_perguntas q
                            where q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  -- FASE 3: a rotina, a equipe, as diárias, a conclusão, os marcos e a comissão. Os "0 obrigatórios": acima do teto, fora
  -- da janela, diária sem confirmação, turno sobrescrito pela agenda, conclusão sem cobrança quando devia, pagamento de
  -- comissão de técnico.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'rotina:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_rot from public.agenda_vigia_rodadas x where x.rotina = 'rotina';
  select count(*) into v_teto
    from (select m.payee_id, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia, m.tipo = 'resposta' as resp, count(*) as n
            from public.agenda_equipe_mensagens m
           where m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
           group by 1, 2, 3) t
   where t.n > case when t.resp then cf.equipe_respostas_dia_max else cf.equipe_proativas_dia_max end;
  -- (revisão C1) pela regra única da janela (_agenda_equipe_fora_da_janela): a resposta direta tem a dela
  select count(*) into v_janela
    from public.whatsapp_send_queue q
    left join public.agenda_equipe_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-equipe'
     and (x.id is null
          or public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.scheduled_for) is not null
          -- o que SAIU fora da janela (o worker atrasado): também conta
          or (q.sent_at is not null and public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.sent_at) is not null));
  v_eq := jsonb_build_object(
    'mensagens_hoje_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select m.tipo, count(*) as n from public.agenda_equipe_mensagens m
         where (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.tipo) t), '{}'::jsonb),
    'recusadas_hoje_por_motivo', coalesce((select jsonb_object_agg(t.recusa_motivo, t.n) from (
        select m.recusa_motivo, count(*) as n from public.agenda_equipe_mensagens m
         where m.estado = 'recusada' and (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.recusa_motivo) t), '{}'::jsonb),
    'acima_do_teto', v_teto, 'fora_da_janela', v_janela);
  select count(*) into v_semconf
    from public.agenda_acoes a
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono' and a.desfeita_em is null
     and coalesce(public._agenda_confirmacao_do_dia(a.payee_id, (a.depois ->> 'dia')::date) ->> 'estado', '') <> 'confirmada';
  select count(*) into v_sobre
    from public.agenda_acoes a left join public.work_shifts ws on ws.id = a.work_shift_id
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono'
     and (coalesce(jsonb_typeof(a.antes -> 'turno'), 'null') <> 'null' or (ws.id is not null and ws.origem <> 'agente'));
  v_dia := jsonb_build_object(
    -- (o dia de quem agiu: a.dia é o p_hoje dele; criada_em é o relógio do banco)
    'lancadas_7d', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'diaria' and a.executada and a.origem <> 'dono' and a.dia > p_hoje - 7),
    'sombra_7d', (select count(*) from public.agenda_acoes a
                   where a.tipo = 'diaria' and not a.executada and a.dia > p_hoje - 7),
    'perguntas_abertas', (select count(*) from public.agenda_perguntas q where q.tipo in ('diaria', 'diaria_ligar') and q.estado = 'aberta'),
    'sem_confirmacao', v_semconf, 'sobrescreveu_turno', v_sobre);
  -- a conclusão pela porta sem cobrança viva quando a regra da condição dá parcelas ou título (a releitura é só service_role)
  if has_function_privilege('public._os_recebiveis_da_conclusao(uuid, date)', 'execute') then
    select count(*) into v_semrec
      from (select distinct so.id, so.check_out_at
              from public.agenda_acoes a join public.service_orders so on so.id = a.service_order_id
             where a.tipo = 'concluir' and a.executada and a.desfeita_em is null and so.status in ('completed', 'invoiced')
               and so.check_out_at is not null
               and not exists (select 1 from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled')) t
     where public._os_recebiveis_da_conclusao(t.id, (t.check_out_at at time zone 'America/Sao_Paulo')::date) ->> 'motivo'
           in ('parcelas', 'titulo_unico');
  end if;
  v_conc := jsonb_build_object(
    'pela_agenda_7d', (select count(*) from public.agenda_acoes a
                        where a.tipo = 'concluir' and a.executada and a.origem in ('equipe', 'dono')
                          and a.dia > p_hoje - 7),
    'desfeitas_7d', (select count(*) from public.agenda_acoes a
                      where a.tipo = 'concluir' and a.desfeita_em > p_agora - interval '7 days'),
    'sem_recebivel_quando_devia', v_semrec);
  select jsonb_build_object(
           'concluidas_30d', count(*),
           'entregues_em_ate_5du', count(*) filter (where so.delivered_at is not null
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date,
                                        (so.delivered_at at time zone 'America/Sao_Paulo')::date) <= cf.entrega_aviso_du),
           'sem_entrega_ha_mais_de_5du', count(*) filter (where so.delivered_at is null and so.status = 'completed'
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date, p_hoje) > cf.entrega_aviso_du))
    into v_marcos
    from public.service_orders so
   where so.check_out_at > p_agora - interval '30 days'
     and exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null);
  select count(*) into v_pay
    from public.payables pa
   where pa.origin = 'commission' and pa.created_at > p_agora - interval '7 days'
     and pa.payee_id in (select w.payee_id from public.work_profiles w where w.modo_pagamento = 'diaria' and w.payee_id is not null);
  v_com := jsonb_build_object('pagamento', (select c.pagamento from public.comissao_config c where c.id),
                              'payables_de_comissao_tecnico_7d', v_pay);
  -- FASE 3: fim
  -- FASE 4: o material (a nota, o Pix, o detector, o cadastro) e a mensagem ao fornecedor. Os "0 obrigatórios": linha
  -- ligada a nota ou Pix sem a palavra do dono (vinculo_sem_resposta_do_dono), previsão sem o original guardado, e na
  -- mensagem ao fornecedor: nada na fila em sombra (ou sem a mensagem registrada), nada saindo ou que saiu fora da janela,
  -- nada acima do teto, nada com valor, pagamento, OS, link ou o nome do cliente.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'material:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_mrod from public.agenda_vigia_rodadas x where x.rotina = 'material';
  select jsonb_build_object(
           'a_caminho', count(*) filter (where r.estado = 'a_caminho'),
           'sem_resposta', count(*) filter (where r.vinculo = 'sem_resposta' and r.estado <> 'descartada'),
           'ligadas_7d', count(*) filter (where r.vinculo = 'ligada' and r.respondida_em > p_agora - interval '7 days'),
           'sem_servico_7d', count(*) filter (where r.vinculo = 'sem_servico' and r.respondida_em > p_agora - interval '7 days'),
           'chegaram_7d', count(*) filter (where r.estado = 'chegou' and r.chegou_em > p_hoje - 7))
    into v_rem from public.material_remessas r;
  v_mperg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q
         where q.estado = 'aberta'
           and q.tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
         group by q.tipo) t), '{}'::jsonb),
    -- o teto do Pix (pix_perguntas_semana_max por semana ISO, no total), no modo de agora
    'pix_na_semana', (select count(*) from public.agenda_perguntas q
                       where q.tipo = 'pix_material'
                         and q.modo = case when cf.modo_material = 'ligado' then 'ligado' else 'sombra' end
                         and (q.criada_em at time zone 'America/Sao_Paulo')::date
                             between date_trunc('week', p_hoje)::date and date_trunc('week', p_hoje)::date + 6));
  -- a linha que a agenda ligou a uma nota ou a um Pix tem de ter a palavra do dono (ou a compra que ele já ligou)
  select count(*) into v_semdono
    from public.os_material m
   where (m.remessa_id is not null or m.fonte in ('nfe', 'pix'))
     and coalesce(m.evidencia ->> 'vinculo_por', '') not in ('dono', 'compra_ligada');
  select count(*) into v_semorig from public.os_material m where m.previsao_ate is not null and m.previsao_original is null;
  -- a precisão do detector é do administrador e do financeiro (para outro login ela lançaria 42501)
  if (select auth.uid()) is null or public.is_admin_or_financial((select auth.uid())) then
    v_prec := public.agenda_detector_precisao(p_hoje - 13, p_hoje);
  end if;
  v_det := jsonb_build_object(
    'sinais_14d', v_prec -> 'sinais', 'julgados_14d', v_prec -> 'julgados', 'certos_14d', v_prec -> 'certos',
    'precisao_14d', v_prec -> 'precisao', 'pronto_para_ligar', coalesce((v_prec ->> 'pronto_para_ligar')::boolean, false),
    'aplicados_7d', (select count(*) from public.material_sinais s where s.estado = 'aplicado' and s.dia > p_hoje - 7),
    'desfeitos_7d', (select count(*) from public.material_sinais s join public.agenda_acoes a on a.id = s.acao_id
                      where a.desfeita_em > p_agora - interval '7 days'));
  -- a mensagem ao fornecedor: o que entrou na fila sem a mensagem registrada em ligado (nada sai em sombra)
  select count(*) into v_fsombra
    from public.whatsapp_send_queue q
    left join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor' and (x.id is null or x.modo <> 'ligado');
  v_fsombra := v_fsombra + (select count(*) from public.agenda_fornecedor_mensagens x
                             where x.modo <> 'ligado' and (x.fila_id is not null or x.estado = 'enfileirada'));
  -- o que está na fila, saindo ou saiu fora da janela da mensagem (pela regra única); o que falhou não saiu
  select count(*) into v_ffora
    from public.whatsapp_send_queue q
    join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor'
     and ((q.status in ('pending', 'sending', 'sent')
           and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.scheduled_for) is not null)
          or (q.sent_at is not null and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.sent_at) is not null));
  -- acima do teto: o que entrou na fila (ligado), por fornecedor no dia e na semana ISO, e no dia a todos
  with ent as (
    select x.fornecedor_id as f, (x.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_fornecedor_mensagens x
     where x.modo = 'ligado'
       and (x.fila_id is not null
            or exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor' and q.source_ref_id = x.id))
  )
  select (select count(*) from (select e.f, e.dia from ent e group by 1, 2 having count(*) > cf.fornecedor_dia_max) a)
       + (select count(*) from (select e.f, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.fornecedor_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.fornecedor_total_dia_max) t)
    into v_fteto;
  select count(*) into v_fproib
    from public.agenda_fornecedor_mensagens x
   where public._agenda_fornecedor_texto_proibido(x.texto, x.service_order_id) is not null;
  select jsonb_build_object(
           'registradas_7d', count(*),
           'enfileiradas_7d', count(*) filter (where x.estado = 'enfileirada'),
           'em_teste_7d', count(*) filter (where x.modo = 'sombra'),
           'recusadas_7d_por_motivo', coalesce((
             select jsonb_object_agg(t.recusa_motivo, t.n) from (
               select y.recusa_motivo, count(*) as n from public.agenda_fornecedor_mensagens y
                where y.estado = 'recusada' and (y.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7
                group by y.recusa_motivo) t), '{}'::jsonb))
    into v_forn
    from public.agenda_fornecedor_mensagens x
   where (x.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7;
  -- a cobertura: os itens críticos das OS que começam nas próximas material_inicio_dias, e quantos têm data (nível A a D)
  select jsonb_build_object(
           'itens_criticos_proximos', count(*),
           'com_previsao', count(*) filter (where e ->> 'nivel' <> 'E'),
           'pct', case when count(*) > 0 then round(100 * (count(*) filter (where e ->> 'nivel' <> 'E'))::numeric / count(*)) end)
    into v_cob
    from (select k.id from unnest(v_cart) k(id)
           where public._agenda_inicio_previsto(k.id, p_hoje) between p_hoje and p_hoje + cf.material_inicio_dias) o
    cross join lateral jsonb_array_elements(coalesce(public.os_prontidao(o.id, p_hoje) #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, false);
  -- a espera: a mediana dos dias corridos da aprovação (a régua de os_carteira) até a 1ª compra (o dia dito ou o da OC),
  -- das OS aprovadas nos últimos 90 dias que já compraram
  select percentile_cont(0.5) within group (order by t.d) into v_med
    from (select min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date))
                 - (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date as d
            from public.service_orders so
            join public.os_material m on m.service_order_id = so.id
            left join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
            left join public.purchase_orders po on po.id = poi.purchase_order_id and po.status <> 'cancelled'
           where so.merged_into_id is null and so.status <> 'cancelled'
             and (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date
                 between p_hoje - 90 and p_hoje
           group by so.id
          having min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date)) is not null) t;
  v_zeros4 := v_semdono = 0 and v_semorig = 0 and v_fsombra = 0 and v_ffora = 0 and v_fteto = 0 and v_fproib = 0;
  v_mat := jsonb_build_object(
    'modos', jsonb_build_object('material', cf.modo_material, 'detector', cf.modo_detector, 'fornecedor', cf.modo_fornecedor),
    'ultima_rodada', v_mrod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_mrod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_mrod -> 'erros_24h',
    'remessas', v_rem, 'perguntas', v_mperg,
    'vinculo_sem_resposta_do_dono', v_semdono, 'previsao_sem_original', v_semorig,
    'detector', v_det,
    'fornecedor', v_forn || jsonb_build_object('na_fila_em_sombra', v_fsombra, 'fora_da_janela', v_ffora,
                                               'acima_do_teto', v_fteto, 'com_valor_ou_cliente', v_fproib),
    'cobertura', v_cob,
    'espera', jsonb_build_object('mediana_ate_comprar_90d', v_med));
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente — o modo, as ondas e os tipos liberados, a rodada, as mensagens e a aprovação em 7 dias.
  -- Os "0 obrigatórios" (entram no ok pelo v_zeros4, para o ok ficar igual linha a linha): nada fora da janela (nem o que
  -- saiu fora dela), nada em feriado ou domingo, nada acima do teto, nada a menos do intervalo de outra, nada com texto
  -- proibido, nada na fila em teste, nada enviado sem a aprovação dos primeiros dias, nada crítico enviado sem a opção 2,
  -- nenhuma véspera com a OS aguardando peça, nenhum aviso de atraso depois da data dita, nenhum áudio que confirmou. As
  -- métricas não reprovam.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'cliente:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_crod from public.agenda_vigia_rodadas x where x.rotina = 'cliente';
  select coalesce(jsonb_object_agg(t.tipo, jsonb_build_object('registradas', t.reg, 'aguardando', t.agu, 'enviadas', t.env,
                                                              'recusadas_por_motivo', t.rec)), '{}'::jsonb)
    into v_cmsg
    from (select m.tipo, count(*) as reg, count(*) filter (where m.estado = 'aguardando_dono') as agu,
                 count(*) filter (where m.enviada_em is not null) as env,
                 coalesce((select jsonb_object_agg(y.recusa_motivo, y.n)
                             from (select z.recusa_motivo, count(*) as n from public.agenda_cliente_mensagens z
                                    where z.tipo = m.tipo and z.estado = 'recusada' and z.criada_em > p_agora - interval '7 days'
                                    group by z.recusa_motivo) y), '{}'::jsonb) as rec
            from public.agenda_cliente_mensagens m
           where m.criada_em > p_agora - interval '7 days'
           group by m.tipo) t;
  select jsonb_build_object(
           'pedidas_abertas', count(*) filter (where m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')),
           'vencidas_7d', count(*) filter (where m.aprovacao = 'vencida' and m.criada_em > p_agora - interval '7 days'),
           'aprovadas_7d', count(*) filter (where m.aprovacao = 'aprovada' and m.aprovada_em > p_agora - interval '7 days'),
           'seguradas_7d', count(*) filter (where m.aprovacao = 'segurada' and m.aprovada_em > p_agora - interval '7 days'))
    into v_caprov from public.agenda_cliente_mensagens m where m.modo = 'ligado';
  -- a janela (a regra única): o que está na fila, saindo ou saiu fora da janela da mensagem; o feriado e o domingo à parte
  select count(*) filter (where t.f is not null), count(*) filter (where t.f in ('feriado', 'domingo'))
    into v_cjan, v_cdom
    from (select coalesce(case when q.status in ('pending', 'sending', 'sent')
                               then public._agenda_cliente_fora_da_janela(x.enviar_em, q.scheduled_for) end,
                          case when q.sent_at is not null then public._agenda_cliente_fora_da_janela(x.enviar_em, q.sent_at) end) as f
            from public.whatsapp_send_queue q
            join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente') t;
  -- o teto: o que entrou na fila (ligado), por cliente no dia e na semana ISO, e no dia a todos
  with ent as (
    select m.client_id as c, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_cliente_mensagens m
     where m.modo = 'ligado' and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')
  )
  select (select count(*) from (select e.c, e.dia from ent e group by 1, 2 having count(*) > cf.cliente_dia_max) a)
       + (select count(*) from (select e.c, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.cliente_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.cliente_total_dia_max) t)
    into v_cteto;
  -- o intervalo: duas linhas agenda-cliente (na fila, saindo ou saídas) a menos de cliente_intervalo_min_s uma da outra
  select count(*) into v_cint
    from public.whatsapp_send_queue a
    join public.whatsapp_send_queue b
      on b.source = 'agenda-cliente' and b.id > a.id and b.status in ('pending', 'sending', 'sent')
     and abs(extract(epoch from coalesce(b.sent_at, b.scheduled_for) - coalesce(a.sent_at, a.scheduled_for)))
         < cf.cliente_intervalo_min_s
   where a.source = 'agenda-cliente' and a.status in ('pending', 'sending', 'sent');
  select count(*) into v_cproib
    from public.agenda_cliente_mensagens m where public._agenda_cliente_texto_proibido(m.texto) is not null;
  -- em teste nada entra na fila (nem linha da fila sem a mensagem registrada em ligado)
  select (select count(*) from public.whatsapp_send_queue q
            left join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente' and (x.id is null or x.modo <> 'ligado'))
       + (select count(*) from public.agenda_cliente_mensagens x
           where x.modo <> 'ligado' and (x.fila_id is not null or x.enviada_em is not null
                                         or x.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')))
    into v_csombra;
  -- enviada sem a aprovação do dono quando o tipo ainda não somava os dias aprovados (ou a preparada pelo dono)
  select count(*) into v_csemap
    from public.agenda_cliente_mensagens m
   where m.modo = 'ligado' and m.enviada_em is not null and m.aprovacao <> 'aprovada'
     and (m.origem <> 'rodada'
          or (cf.cliente_aprovacao_dias > 0
              and (select count(distinct (y.aprovada_em at time zone 'America/Sao_Paulo')::date)
                     from public.agenda_cliente_mensagens y
                    where y.tipo = m.tipo and y.aprovacao = 'aprovada' and y.origem = 'rodada' and y.modo = 'ligado'
                      and y.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias));
  -- a crítica enviada sem a decisão "2) eu mando o aviso escrito"
  select count(*) into v_ccrit
    from public.agenda_cliente_mensagens m
    left join public.agenda_perguntas q on q.id = m.pergunta_id
   where m.enviada_em is not null
     and (m.aprovacao = 'critica'
          or (q.tipo = 'cliente_aviso' and not (q.estado = 'respondida' and q.opcao_escolhida = 2)));
  -- a véspera (M2/M4) enviada com a OS aguardando peça (no registro, ou pela última mudança de status antes do envio)
  select count(*) into v_cvesp
    from public.agenda_cliente_mensagens m
   where m.tipo in ('vespera', 'acesso') and m.enviada_em is not null
     and (m.base ->> 'status' = 'awaiting_parts'
          or (select a.status_depois from public.agenda_acoes a
               where a.service_order_id = m.service_order_id and a.tipo = 'status' and a.executada
                 and a.criada_em <= m.enviada_em
               order by a.criada_em desc, a.id desc limit 1) = 'awaiting_parts');
  -- o aviso de atraso enviado depois da data que o cliente ouviu
  select count(*) into v_cdepois
    from public.agenda_cliente_mensagens m
   where m.tipo = 'pode_atrasar' and m.enviada_em is not null and m.base ? 'prometido_ate'
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date > (m.base ->> 'prometido_ate')::date;
  select count(*) into v_caudio
    from public.agenda_cliente_respostas r where r.tipo_msg = 'audio' and r.efeito = 'confirmou';
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'm6_antes_da_data_pct_90d', (
      select case when count(*) > 0 then round(100 * (count(*) filter (
               where (m.enviada_em at time zone 'America/Sao_Paulo')::date <= (m.base ->> 'prometido_ate')::date))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.tipo = 'pode_atrasar' and m.enviada_em > p_agora - interval '90 days' and m.base ? 'prometido_ate'),
    'aprovadas_sem_segurar_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where m.aprovacao = 'aprovada'))::numeric / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.modo = 'ligado' and m.aprovacao in ('aprovada', 'segurada') and m.aprovada_em > p_agora - interval '30 days'),
    'resposta_24h_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.recebida_em <= m.enviada_em + interval '1 day'))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
        left join public.agenda_cliente_respostas r on r.id = m.resposta_id
       where m.modo = 'ligado' and m.enviada_em > p_agora - interval '30 days'
         and m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')),
    'sim_automatico_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.efeito = 'confirmou'))::numeric / count(*)) end
        from public.agenda_cliente_respostas r
       where r.modo = 'ligado' and r.recebida_em > p_agora - interval '30 days' and r.intencao = 'confirma'),
    'opt_outs_30d', (select count(*) from public.agenda_cliente_respostas r
                      where r.intencao = 'opt_out' and r.recebida_em > p_agora - interval '30 days'),
    'falhas_de_entrega_30d', (select count(*) from public.whatsapp_send_queue q
                               where q.source = 'agenda-cliente' and q.status = 'failed'
                                 and q.created_at > p_agora - interval '30 days'),
    'idas_perdidas_por_acesso_90d', (
      select jsonb_build_object('com_aviso', count(*) filter (where t.avisado), 'sem_aviso', count(*) filter (where not t.avisado))
        from (select distinct a.service_order_id, a.dia,
                     exists (select 1 from public.agenda_cliente_mensagens m
                              where m.service_order_id = a.service_order_id and m.tipo in ('vespera', 'acesso')
                                and m.enviada_em is not null and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = a.dia) as avisado
                from public.agenda_alocacoes a
               where a.resultado = 'nao_cumprido' and a.motivo = 'cliente_ou_bem' and a.dia > p_hoje - 90 and a.dia <= p_hoje) t))
    into v_cmet;
  v_zeros5 := v_cjan = 0 and v_cdom = 0 and v_cteto = 0 and v_cint = 0 and v_cproib = 0 and v_csombra = 0 and v_csemap = 0
              and v_ccrit = 0 and v_cvesp = 0 and v_cdepois = 0 and v_caudio = 0;
  v_zeros4 := v_zeros4 and v_zeros5;
  v_cli := jsonb_build_object(
    'modo', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
    'tipos_liberados', to_jsonb(array(select t from unnest(array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                                  'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                                  'pos_servico', 'mudanca_no_dia']) t
                                       where public._agenda_cliente_tipo_liberado(t))),
    'ultima_rodada', v_crod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_crod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_crod -> 'erros_24h',
    'mensagens_7d', jsonb_build_object('por_tipo', v_cmsg),
    'aprovacao', v_caprov,
    'fora_da_janela', v_cjan, 'em_feriado_ou_domingo', v_cdom, 'acima_do_teto', v_cteto, 'intervalo_curto', v_cint,
    'com_texto_proibido', v_cproib, 'na_fila_em_sombra', v_csombra, 'sem_aprovacao_no_periodo', v_csemap,
    'critica_sem_decisao', v_ccrit, 'vespera_com_os_aguardando_peca', v_cvesp, 'aviso_depois_da_data', v_cdepois,
    'audio_que_confirmou', v_caudio,
    'metricas', v_cmet);
  -- FASE 5: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros obrigatórios de antes do aprendizado (o bloco do aprendizado os junta aos dele; o
  -- bloco da C2 depois dele refaz essa junta com as janelas de agenda_config)
  v_z4_antes := v_zeros4;
  -- CORREÇÃO FASE 6: fim
  -- FASE 6: (P6) o aprendizado (spec-fase6 §11) — o modo, a lista, a rodada, os itens e as métricas. Os "0 obrigatórios"
  -- (entram no ok pelo v_zeros4, como os das Fases 4 e 5): nada em uso com menos medidas que o mínimo; nada que a ÚLTIMA
  -- rodada gravou em uso com o modo dela fora de ligado ou o item fora da lista dela (logo depois de o dono desligar, o leitor
  -- já devolve o padrão; a linha muda na rodada seguinte); nenhuma troca grande que entrou sozinha (as ações da vigia em 7 dias
  -- contra os limites de hoje: a regra de _agenda_aprendizado_troca_cabe, que não tem porta para quem lê a saúde); nenhuma
  -- rodada atrasada (depois da 1ª, nenhuma em 26 h); nenhuma medida sem classe; nenhum fator fora de [fator_min, fator_max].
  -- Os erros de aprender:% em 24 h e as métricas não reprovam.
  select x.p_agora, x.p_hoje, x.contagens into v_arod
    from public.agenda_vigia_rodadas x where x.rotina = 'aprender'
   order by x.p_agora desc, x.rodou_em desc, x.id desc limit 1;
  select count(*) into v_apeq
    from public.agenda_aprendizado a
   where a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null and a.n < a.n_min;
  select count(*) into v_afora
    from public.agenda_aprendizado a
   where v_arod.p_agora is not null and a.estado = 'em_uso' and a.em_uso is not null and a.calculado_em >= v_arod.p_agora
     and (coalesce(v_arod.contagens ->> 'modo_aprendizado', '') <> 'ligado'
          or not coalesce(v_arod.contagens -> 'ligados' ? public._agenda_aprendizado_da_lista(a.item), false));
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '7 days'
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null and v_arod.p_agora < p_agora - interval '26 hours' then 1 else 0 end;
  select count(*) into v_asemcl from public.agenda_medidas_os m where m.classe_bem is null or m.classe_sistema is null;
  select count(*) into v_afat
    from public.agenda_aprendizado a
   where a.item = 'fator'
     and ((a.calculado is not null and a.calculado not between cf.fator_min and cf.fator_max)
          or (a.em_uso is not null and a.em_uso not between cf.fator_min and cf.fator_max));
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'itens', coalesce((select jsonb_object_agg(t.item, jsonb_build_object('chaves', t.chaves, 'n_max', t.n_max, 'n_min', t.n_min,
                                                                         'estados', t.estados))
                         from (select a.item, count(*) as chaves, max(a.n) as n_max, max(a.n_min) as n_min,
                                      (select jsonb_object_agg(s.estado, s.n)
                                         from (select b.estado, count(*) as n from public.agenda_aprendizado b
                                                where b.item = a.item group by b.estado) s) as estados
                                 from public.agenda_aprendizado a group by a.item) t), '{}'::jsonb),
    'medidas', (select jsonb_build_object('total', count(*), 'validas', count(*) filter (where m.valida),
                                          'invalidas', coalesce((select jsonb_object_agg(y.motivo, y.n)
                                                                   from (select z.motivo, count(*) as n from public.agenda_medidas_os z
                                                                          where not z.valida
                                                                            and z.concluida_em > p_hoje - cf.aprender_janela_dias
                                                                          group by z.motivo) y), '{}'::jsonb))
                  from public.agenda_medidas_os m where m.concluida_em > p_hoje - cf.aprender_janela_dias),
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '30 days'),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - interval '30 days'),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida' and q.respondida_em > p_agora - interval '30 days'),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '30 days')),
    -- o erro do fator: das OS válidas concluídas depois que o fator da classe delas passou a valer, quantas ficaram dentro dele
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t),
    -- a pontualidade com o cliente antes e depois de a folga do aviso valer
    'pontualidade_folga', (select case when f.desde is not null then jsonb_build_object(
                                     'desde', f.desde,
                                     'antes_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                    where m.atraso_cliente_du is not null and m.concluida_em < f.desde),
                                     'depois_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                     where m.atraso_cliente_du is not null and m.concluida_em >= f.desde)) end
                             from (select (min(a.em_uso_desde) at time zone 'America/Sao_Paulo')::date as desde
                                     from public.agenda_aprendizado a where a.item = 'aviso_folga' and a.em_uso is not null) f),
    -- parar (§11): o item que o dono desfez 2 vezes em 4 semanas (recomendar tirá-lo da lista; a decisão é dele)
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '28 days'
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb))
    into v_amet;
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_zeros4 and v_zeros6;
  v_apr := jsonb_build_object(
    'modo', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
    'ultima_rodada', v_arod.p_agora,
    'rodou_hoje', exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = p_hoje),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'aprender:%'
                     and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'em_uso_com_amostra_pequena', v_apeq, 'em_uso_fora_de_ligado', v_afora, 'troca_grande_sem_pergunta', v_agrande,
    'rodada_atrasada', v_aatras, 'medida_sem_classe', v_asemcl, 'fator_fora_dos_limites', v_afat,
    'metricas', v_amet);
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: as janelas do aprendizado na saúde vêm de agenda_config (eram números escritos aqui): a
  -- troca grande que entrou sozinha, nas ações dos últimos aprender_saude_dias (era 7 dias); a rodada atrasada, sem rodada há
  -- mais de aprender_atraso_h (era 26 h); as trocas das métricas, nos últimos aprender_parar_dias (era 30 dias; a chave
  -- trocas_30d fica com o nome); o item desfeito 2 vezes dentro de aprender_trava_dias (era 28 dias, as "4 semanas" da §11).
  -- As contas de cima não valem mais: refeitas aqui com o parâmetro (com os DEFAULTs, o mesmo resultado), e com elas os
  -- zeros, o ok e o bloco aprendizado.
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
     and a.criada_em > p_agora - make_interval(days => cf.aprender_saude_dias)
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null
                        and v_arod.p_agora < p_agora - make_interval(hours => cf.aprender_atraso_h) then 1 else 0 end;
  v_amet := v_amet || jsonb_build_object(
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
                      and a.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida'
                       and q.respondida_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - make_interval(days => cf.aprender_parar_dias))),
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado'
                                                     and a.desfeita_em > p_agora - make_interval(days => cf.aprender_trava_dias)
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb));
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_z4_antes and v_zeros6;
  v_apr := v_apr || jsonb_build_object('troca_grande_sem_pergunta', v_agrande, 'rodada_atrasada', v_aatras, 'metricas', v_amet);
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P7, spec §11) o bloco gestor: os modos efetivos, a última rodada (rotina gestor), os erros de gestor:% em 24 h, os
  -- zeros obrigatórios (entram no ok, salvo prazo_vencido_sem_mostrar, que só se conta: a pergunta fica aberta) e os números. Os
  -- zeros do que o gestor muda sozinho contam a partir do OK de ligar (marcar_sozinho_desde): antes dele não há o que contar.
  -- E (aviso do P6) o erro do fator só com as medidas que têm fator: a medida por estimativa é válida e não tem fator.
  v_gdesde := cf.marcar_sozinho_desde;
  v_gmodos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                 'revisao', public._agenda_gestor_modo('revisao'), 'compre_ate', public._agenda_gestor_modo('compre_ate'),
                                 'vaga', public._agenda_gestor_modo('vaga'), 'so_propor', cf.gestor_so_propor, 'desde', v_gdesde);
  select max(x.p_agora) as ultima,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         coalesce(bool_or(x.p_hoje = p_hoje and x.contagens ? 'diaria'), false) as diaria_hoje,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_gult from public.agenda_vigia_rodadas x where x.rotina = 'gestor';
  v_gz := jsonb_build_object(
    -- o dia que o cliente ouviu e o dia que a equipe já sabia, mudados sem a pergunta crítica (a regra de _agenda_criticidade_da_acao)
    'zona_travada_mexida', (select count(*) from public.agenda_acoes a
                             where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                               and a.origem in ('motor', 'vigia', 'conferencia')
                               and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                               and public._agenda_criticidade_da_acao(a.id) = 'dia_prometido'),
    'dia_avisado_sem_pergunta', (select count(*) from public.agenda_acoes a
                                  where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                    and a.origem in ('motor', 'vigia', 'conferencia')
                                    and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                                    and public._agenda_criticidade_da_acao(a.id) = 'dia_avisado'),
    -- marcada pela estimativa sem a pergunta que ela pedia (grande, começada/parada, sem mão de obra, peça embutida)
    'estimativa_sem_pergunta', case when not public._agenda_gestor_regra('estimativa') then 0 else (
       select count(*) from (select distinct a.service_order_id as os from public.agenda_alocacoes a
                               left join public.os_planejamento pl on pl.service_order_id = a.service_order_id
                              where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                                and a.resultado is null and a.duracao_fonte = 'orcamento' and pl.dias is null) o
        where coalesce(public._agenda_gestor_estimativa(o.os, p_hoje) ->> 'motivo', '') in ('grande', 'situacao', 'sem_base', 'embutida')) end,
    'prazo_em_critica', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.critica and q.veto_ate is not null),
    'prazo_em_dia_prometido', (select count(*) from public.agenda_perguntas q
                                where q.estado = 'aberta' and q.veto_ate is not null and q.tipo = 'dia_prometido'),
    -- aprovada há mais de aprovada_sem_data_min sem dia, sem reserva, sem pergunta aberta e sem o motor ter dito por que fica de
    -- fora depois da aprovação (com o encaixe na aprovação ligado: antes dele, quem encaixa é a vigia e a publicação)
    'aprovada_sem_data', case when public._agenda_gestor_modo('encaixe') <> 'ligado' then 0 else (
       select count(*) from public.os_carteira(p_hoje) k join public.service_orders so on so.id = k.service_order_id
        where coalesce(so.converted_to_os_at, so.signed_at) is not null
          and coalesce(so.converted_to_os_at, so.signed_at) < p_agora - make_interval(mins => cf.aprovada_sem_data_min)
          and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = k.service_order_id
                           and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null)
          and not exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' and q.service_order_id = k.service_order_id)
          and not exists (select 1 from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
                           where pr.criada_em >= coalesce(so.converted_to_os_at, so.signed_at)
                             and (f ->> 'os')::uuid = k.service_order_id)) end,
    -- sem rodada do gestor em 40 min, de 07:30 a 21:00 de dia útil, com algum modo do gestor fora de desligado
    'rodada_gestor_atrasada', case when (v_gmodos ->> 'marcar' <> 'desligado' or v_gmodos ->> 'encaixe' <> 'desligado'
                                         or v_gmodos ->> 'revisao' <> 'desligado' or v_gmodos ->> 'compre_ate' <> 'desligado')
                                        and public.agenda_dia_util(p_hoje)
                                        and (p_agora at time zone 'America/Sao_Paulo')::time between time '07:30' and time '21:00'
                                        and coalesce(v_gult.ultima < p_agora - interval '40 minutes', true) then 1 else 0 end,
    -- a mensagem ao cliente por estimativa que saiu sem o sim do dono antes de somar cliente_aprovacao_dias dias aprovados
    'cliente_estimativa_sem_aprovacao', (
       select count(*) from public.agenda_cliente_mensagens m
        where v_gdesde is not null and m.criada_em >= v_gdesde and m.base -> 'dados' ->> 'por_estimativa' = 'true'
          and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta') and m.aprovacao <> 'aprovada'
          and (select count(distinct (n.aprovada_em at time zone 'America/Sao_Paulo')::date) from public.agenda_cliente_mensagens n
                where n.tipo = m.tipo and n.base -> 'dados' ->> 'por_estimativa' = 'true' and n.aprovacao = 'aprovada'
                  and n.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias),
    -- a ficha de um dia por estimativa que saiu na janela de veto sem a pergunta ficha_estimativa mostrada (ou segurada com 2)
    'ficha_estimativa_sem_veto', (
       select count(*) from public.agenda_equipe_mensagens em
        where v_gdesde is not null and em.tipo = 'ficha' and em.modo = 'ligado'
          and em.estado in ('enfileirada', 'respondida', 'sem_resposta')
          and em.dia >= (v_gdesde at time zone 'America/Sao_Paulo')::date
          and em.dia < (v_gdesde at time zone 'America/Sao_Paulo')::date + cf.ficha_veto_dias
          and exists (select 1 from public.agenda_alocacoes a where a.payee_id = em.payee_id and a.dia = em.dia
                       and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento')
          and not exists (select 1 from public.agenda_perguntas q
                           where q.chave = 'ficha_estimativa:' || em.payee_id || ':' || em.dia and q.mostrada_vezes > 0
                             and q.opcao_escolhida is distinct from 2)),
    -- a rodada que mudou o dia de mais de gestor_k_os OS de uma vez sem a pergunta onda
    'onda_aplicada_sem_pergunta', (
       select count(*) from (select a.proposta_id from public.agenda_acoes a
                               where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                 and a.origem in ('motor', 'vigia') and a.tipo = 'mover' and a.proposta_id is not null
                               group by a.proposta_id having count(distinct a.service_order_id) > cf.gestor_k_os) p
        where not exists (select 1 from public.agenda_perguntas q where q.tipo = 'onda' and q.proposta_id = p.proposta_id)),
    -- o compromisso novo sem de onde veio a duração (o gatilho _agenda_alocacao_fonte grava em toda alocação nova)
    'alocacao_sem_fonte', (select count(*) from public.agenda_alocacoes a
                            where v_gdesde is not null and a.criado_em >= v_gdesde and a.tipo <> 'reserva' and a.duracao_fonte is null),
    -- a ação do gestor feita numa rodada em que o modo dela não estava ligado (estimar: marcar; reestimar e reparar: revisao)
    'regra_em_sombra_aplicada', (
       select count(*) from public.agenda_acoes a
        where a.executada and a.origem = 'vigia' and a.tipo in ('estimar', 'reestimar', 'reparar')
          and a.criada_em > p_agora - interval '7 days'
          and coalesce((select r.contagens -> 'modos' ->> case when a.tipo = 'estimar' then 'marcar' else 'revisao' end
                          from public.agenda_vigia_rodadas r
                         where r.rotina = 'gestor' and r.p_agora <= a.criada_em
                         order by r.p_agora desc, r.rodou_em desc limit 1), 'desligado') <> 'ligado'),
    -- a pergunta com prazo vencido que o dono nunca viu antes do prazo: fica aberta (aqui só se conta; não entra no ok)
    'prazo_vencido_sem_mostrar', (select count(*) from public.agenda_perguntas q
                                   where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora
                                     and not coalesce(q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false)));
  v_gzeros := not exists (select 1 from jsonb_each(v_gz) z where z.key <> 'prazo_vencido_sem_mostrar' and (z.value)::text <> '0');
  v_ges := jsonb_build_object(
    'modos', v_gmodos, 'regras', to_jsonb(cf.marcar_regras),
    'ultima_rodada', v_gult.ultima, 'rodadas_24h', coalesce(v_gult.n24, 0), 'diaria_hoje', coalesce(v_gult.diaria_hoje, false),
    'erros_ultima_rodada', coalesce(v_gult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'gestor:%' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'zeros_ok', v_gzeros,
    'numeros', jsonb_build_object(
      'os_por_estimativa', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                             where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                               and a.resultado is null and a.duracao_fonte = 'orcamento'),
      'perguntas_com_prazo', jsonb_build_object(
        'abertas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null),
        'vencidas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora),
        'respondidas_7d', (select count(*) from public.agenda_perguntas q where q.estado = 'respondida' and q.veto_ate is not null
                             and q.respondida_em > p_agora - interval '7 days'),
        'pelo_prazo_7d', (select count(*) from public.agenda_acoes a where a.tipo = 'estimar' and a.origem = 'vigia' and a.executada
                            and a.criada_em > p_agora - interval '7 days')),
      'compre_ate', jsonb_build_object(
        'gravados', (select count(*) from public.os_material m where m.compre_ate is not null),
        'cobrados', (select count(*) from public.os_material m where m.cobrado_vezes > 0),
        'empurrados', (select count(*) from public.os_material m where m.empurrada_vezes > 0)),
      'fichas_seguradas_7d', (select count(*) from public.agenda_equipe_mensagens em
                               where em.recusa_motivo = 'veto' and em.criada_em > p_agora - interval '7 days'))) || v_gz;
  v_amet := v_amet || jsonb_build_object(
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.fator is not null
                                 and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t));
  v_apr := v_apr || jsonb_build_object('metricas', v_amet);
  v_gr := jsonb_build_object(
    -- os zeros obrigatórios da execução (a Fase 3), do material e da mensagem ao fornecedor (a Fase 4) e os do gestor entram no ok
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          and v_zeros4
          and v_gzeros,
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    'cliente', v_cli,
    'aprendizado', v_apr,
    'material', v_mat,
    'gestor', v_ges);
  return v_gr;
  -- FASE 7: fim
  return jsonb_build_object(
    -- FASE 3: os zeros obrigatórios da execução entram no ok.
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          -- FASE 4: os zeros obrigatórios do material e da mensagem ao fornecedor entram no ok.
          and v_zeros4,
          -- FASE 4: fim
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    -- FASE 3
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    -- FASE 5: a mensagem ao cliente
    'cliente', v_cli,
    -- FASE 5: fim
    -- FASE 6: o aprendizado
    'aprendizado', v_apr,
    -- FASE 6: fim
    -- FASE 4: o material
    'material', v_mat);
    -- FASE 4: fim
end;
$function$;

comment on function public.agenda_saude(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros. Fase 4 (P5): o bloco material — modos (material, detector, fornecedor), a rodada do material (rotina = material: última, rodou nas últimas 2 h, erros 24 h em material:%), remessas (a caminho, sem resposta, ligadas/sem serviço/chegaram em 7 dias), perguntas (as abertas da Fase 4 por tipo; pix_na_semana), detector (agenda_detector_precisao dos últimos 14 dias — só para administrador/financeiro ou sem login —, aplicados e desfeitos em 7 dias), fornecedor (registradas, enfileiradas, em teste e recusadas por motivo em 7 dias), cobertura (itens críticos das OS que começam nas próximas material_inicio_dias e quantos têm data, nível A–D), espera (mediana da aprovação à 1ª compra, OS aprovadas em 90 dias); os zeros obrigatórios entram no ok: vinculo_sem_resposta_do_dono, previsao_sem_original e, do fornecedor, na_fila_em_sombra, fora_da_janela, acima_do_teto e com_valor_ou_cliente. Fase 5 (P3): o bloco cliente — modo, tipos_ligados, tipos_liberados (somaram cliente_aprovacao_dias dias aprovados), a rodada do cliente (rotina = cliente: última, rodou nas últimas 2 h, erros 24 h em cliente:%), mensagens_7d por tipo (registradas, aguardando, enviadas, recusadas por motivo), aprovacao (pedidas abertas, vencidas, aprovadas e seguradas em 7 dias) e as métricas (M6 antes da data, aprovadas sem segurar, resposta em 1 dia, SIM automático, opt-outs, falhas de entrega, idas perdidas por acesso com e sem véspera); os zeros obrigatórios entram no ok: fora_da_janela, em_feriado_ou_domingo, acima_do_teto, intervalo_curto, com_texto_proibido, na_fila_em_sombra, sem_aprovacao_no_periodo, critica_sem_decisao, vespera_com_os_aguardando_peca, aviso_depois_da_data e audio_que_confirmou. Fase 6 (P6): a chave aprendizado — o modo, a lista, a última rodada, os erros de aprender:% em 24 h, os 6 zeros (em_uso_com_amostra_pequena, em_uso_fora_de_ligado, troca_grande_sem_pergunta, rodada_atrasada, medida_sem_classe, fator_fora_dos_limites; entram no ok) e as métricas (itens, medidas, trocas em 30 dias, o erro do fator, a pontualidade antes e depois da folga, o item desfeito 2 vezes em 4 semanas). CORREÇÃO FASE 6 (C2, item 12): as janelas do aprendizado vêm de agenda_config — a troca grande em aprender_saude_dias, a rodada atrasada em aprender_atraso_h, as métricas das trocas em aprender_parar_dias e o desfeito 2 vezes em aprender_trava_dias. FASE 7 (7a P7, spec §11): a chave gestor — os modos efetivos (marcar, encaixe, revisao, compre_ate, vaga, so_propor, desde), as regras, a última rodada (rotina gestor), as rodadas em 24 h, se os passos diários rodaram hoje, os erros de gestor:% em 24 h, os zeros obrigatórios (entram no ok: zona_travada_mexida e dia_avisado_sem_pergunta pela regra de _agenda_criticidade_da_acao, estimativa_sem_pergunta, prazo_em_critica, prazo_em_dia_prometido, aprovada_sem_data, rodada_gestor_atrasada, cliente_estimativa_sem_aprovacao, ficha_estimativa_sem_veto, onda_aplicada_sem_pergunta, alocacao_sem_fonte, regra_em_sombra_aplicada; os do que o gestor muda sozinho contam a partir de marcar_sozinho_desde) e prazo_vencido_sem_mostrar (só se conta: fica fora do ok), e os números (OS por estimativa, perguntas com prazo abertas/vencidas/respondidas/aplicadas pelo prazo, compre até gravados/cobrados/empurrados, fichas seguradas). E o erro do fator (métricas do aprendizado) só com as medidas que têm fator (a medida por estimativa é válida e não tem fator).';

-- ── 3. O job agenda-gestor (pg_cron; spec §3.1 item 13) ───────────────────────────────────────────────────────────
-- '7,22,37,52 10-23 * * 1-6' = 07:07 a 20:52 de Brasília (UTC−3, sem horário de verão), de segunda a sábado, nos minutos fora
-- dos :00/:15/:30/:45 da vigia (task-automations). Duas instruções: a 1ª põe o statement_timeout da configuração
-- (gestor_tempo_max em segundos, "45s"; nenhum número escrito aqui) e a 2ª roda o gestor — o tempo vale para cada instrução da mensagem, e o da 1ª
-- já vale para a 2ª. Só agenda com a extensão pg_cron (a bancada PGlite não tem: o bloco não faz nada lá; o R8 do teste confere
-- o comando pelo texto). Idempotente: desagenda o de mesmo nome antes. Para tirar: select cron.unschedule('agenda-gestor');
-- No 1º tique depois de aplicar, conferir em cron.job_run_details que as duas instruções rodaram; se o pg_cron recusar duas
-- instruções, o plano B (OK nomeado, porque cria papel) é cron.schedule_in_database(…, username := 'agenda_gestor'), um papel
-- sem login com statement_timeout próprio.
do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'agenda-gestor: sem pg_cron (bancada) — nada agendado';
    return;
  end if;
  if exists (select 1 from cron.job where jobname = 'agenda-gestor') then
    perform cron.unschedule('agenda-gestor');
  end if;
  perform cron.schedule('agenda-gestor', '7,22,37,52 10-23 * * 1-6',
    $job$select set_config('statement_timeout', (select ceil(extract(epoch from c.gestor_tempo_max))::int::text || 's' from public.agenda_config c where c.id), false); select public.agenda_gestor_rodar(public._hoje_brt(), now());$job$);
  if (select count(*) from cron.job where jobname = 'agenda-gestor') <> 1 then
    raise exception 'cron agenda-gestor não ficou com exatamente 1 job';
  end if;
end
$cron$;

-- ── 4. Portas (as de antes das recriadas continuam: create or replace não mexe no grant) ─────────────────────────────────
-- As novas: a rodada e a palavra só pelo service_role (o job do pg_cron roda como o dono do banco; o WhatsApp chama a palavra pela
-- camada da agenda); os passos e os ajudantes de texto sem grant a ninguém (só a rodada e as leituras de dentro); o foco é lido
-- por agenda_ver (invoker, authenticated + service_role) — o ajudante do foco e os de texto que ele usa leem com o login de quem
-- pergunta (a RLS do admin vale).
revoke all on function public.agenda_gestor_rodar(date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_gestor_rodar(date, timestamptz) to service_role;
revoke all on function public.agenda_gestor_dito(uuid, boolean, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_gestor_dito(uuid, boolean, date, timestamptz) to service_role;
revoke all on function public._agenda_gestor_sombra(date, timestamptz), public._agenda_gestor_perguntas(date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public._agenda_ver_gestor(date), public._agenda_plano_estimativa(jsonb, date),
  public._agenda_gestor_motivo_texto(text), public._agenda_gestor_motivo_ordem(text), public._agenda_gestor_faixa(date, date),
  public._agenda_gestor_pessoas(jsonb), public._agenda_gestor_compra_da_os(uuid, date), public._agenda_gestor_dupla_texto(jsonb)
  from public, anon;
grant execute on function public._agenda_ver_gestor(date), public._agenda_plano_estimativa(jsonb, date),
  public._agenda_gestor_motivo_texto(text), public._agenda_gestor_motivo_ordem(text), public._agenda_gestor_faixa(date, date),
  public._agenda_gestor_pessoas(jsonb), public._agenda_gestor_compra_da_os(uuid, date), public._agenda_gestor_dupla_texto(jsonb)
  to authenticated, service_role;
