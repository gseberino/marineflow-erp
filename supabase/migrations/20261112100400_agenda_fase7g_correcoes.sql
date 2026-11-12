-- Agenda de Produção, Fase 7, etapa 7g ("Mostrar como pensou e provar o trabalho"), pacote P5: as marcações medidas e o tipo de OS em teste.
-- A agenda passa a guardar, uma vez por dia, cada marcação que fez (uma linha por ação executada e OS que criou meio-dia que não é reserva) e o que aconteceu
-- com a do gestor antes do 1º dia: o dono desfez, ajustou (a duração, a pessoa, o dia, tirou ou o material), o próprio gestor remarcou, a OS saiu, ou chegou o
-- 1º dia sem nada disso. E calcula, por tipo de OS (a classe de campo), o que o rebaixar do AG7-25 faria: só o "teria" e o texto, sem mudar nada.
-- Spec: scratchpad agenda-pesquisa/spec-fase7g.md (§3.1 itens 7 e 8, §5.5 e o bloco R9, que vale sobre o corpo: R9.3-1 (a saída do dono não é correção),
-- R9.4-2 (sem olhar para trás, o silêncio não é aceite, as 4 formas do histórico, a régua do desfeita), R9.4-4 (o ok do dono é do P5b), R9.5-7, 8, 9 e 21,
-- R9.12, R9.13: "Encolhe — _agenda_explicar_tipos só com teria; agenda_explicar_rodar, agenda-explicar.ts, index.ts"); o registro do pacote: notas-fase7g.md (seção P5).
-- Depende das Fases 1 a 6, das etapas 7a a 7d, da 7f inteira, da 7e inteira e da 7g até o P4 (20261112100000: agenda_marcacoes, agenda_tipos_os, os modos,
-- marcacoes_desde, correcao_janela_du, os parâmetros do rebaixar, explicar_hora, explicar_tempo_max, a rotina explicar; 20261112100100: zona e degrau na ação).
--
-- ═══ DDL — OK NOMEADO ═══ (4 funções novas: 1 SECURITY DEFINER com porta, só service_role; 3 invoker, só service_role. Nenhuma recriada.)
-- NÃO APLICADA. Existe para revisão e espera o OK.
--
-- POR QUE: a agenda não mede o que o dono corrige. Sem a medida, o placar da quinta (P6) não tem o que dizer das marcações, e o "espera o seu ok" do AG7-25
-- (P5b) não tem amostra. Esta migration cria a medida e o "teria", e nada mais: nenhuma mensagem, nenhum nível, nenhuma reserva.
--
-- O QUE MUDA (com modo_porque, modo_rebaixar e modo_placar desligados, nada: a rodada devolve {rodou: false, desligado} sem gravar linha):
--   1. agenda_explicar_rodar (nova; SECURITY DEFINER; com login só admin/financeiro, 42501; grant só ao service_role): a rodada explicar, pelo task-automations
--      a cada tique (agenda-explicar.ts), uma vez por dia (R9.5-9, o molde de agenda_aprender): domingo nada; antes de explicar_hora, {cedo}; a 2ª do dia,
--      {ja_rodou}; nenhuma dessas grava linha. Passos, cada um no seu bloco: marcacoes (modo_porque fora de desligado), tipos (modo_rebaixar fora de desligado)
--      e, no dia_do_plano, placar (modo_placar fora de desligado; a função é do P6: sem ela, o passo nem entra). O relógio explicar_tempo_max, conferido antes de
--      cada passo (R9.5-8: sem statement_timeout na definição); erro de um passo → app_error_logs (agenda, explicar:<passo>) e segue; query_canceled → registra,
--      grava a rodada com parou_no e encerra (o tique seguinte vê a rodada do dia e não repete). Uma linha em agenda_vigia_rodadas (rotina explicar).
--   2. _agenda_explicar_marcacoes (nova, invoker): (1) registra em agenda_marcacoes, com on conflict do nothing (2× = 1×), as ações executadas desde
--      agenda_config.marcacoes_desde (nula: nenhuma; R9.4-2, sem olhar para trás) e até p_agora, de tipo publicar, criar, mover, promover_reserva, fixar,
--      reparar ou reestimar, que criaram meio-dia de turno que não é reserva — uma linha por (ação, OS), com quem marcou (_agenda_quem_marcou), a classe, a
--      fonte e as suposições da 1ª alocação, o período, as pessoas, a 1ª hora, a aprovação (coalesce(converted_to_os_at, signed_at, created_at), R9.5-7) e a
--      zona e o degrau da ação. A origem cliente (da ação ou de uma alocação) não entra (R9.4-2). (2) decide as abertas do gestor por _agenda_marcacao_desfecho.
--   3. _agenda_marcacao_desfecho (nova, invoker, STABLE): o desfecho de uma marcação do gestor, nesta ordem: desfeita (desfeita por quem não é o motor, a vigia
--      nem o cliente: a régua de _agenda_gestor_desfeito, R9.4-2); ajustada (antes do 1º dia: ação do dono na OS — criar, mover, cancelar, fixar que mudou o
--      lugar —, o histórico de os_planejamento com dias, equipe ou dupla diferentes, ou material da OS com fonte dono); remarcada (o gestor ou o cliente tirou
--      meio-dia dela antes do 1º dia); saiu (a OS saiu da carteira: os_saiu); aceita (chegou o 1º dia; ou correcao_janela_du dias úteis sem 1º dia); senão
--      aberta. conferida = algum meio-dia dela com resultado cumprido ou parcial na hora do desfecho (R9.4-2: o silêncio não é aceite).
--   4. _agenda_explicar_tipos (nova, invoker): para cada classe com marcação do gestor, a amostra do AG7-25 (as rebaixar_amostra mais novas decididas — aceita,
--      ajustada, desfeita — nas rebaixar_janela_semanas) e o que o rebaixar faria (teria: espera_ok com n ≥ rebaixar_n_min e corrigidas ÷ n ≥ rebaixar_taxa,
--      fora da trava) e o texto do §6.4 ("Em teste: nas OS de energia em motorhome eu passaria a esperar o seu ok (você corrigiu 3 de 4)."). O nível não muda
--      (é do P5b, R9.4-4): em qualquer modo fora de desligado, só teria e texto.
--
-- O QUE NÃO MUDA: o motor, a vigia, as propostas, o que se aplica, o que se lê, as perguntas, as mensagens. Nenhuma função de antes é recriada; nenhuma lê as
-- tabelas que esta enche. O histórico de os_planejamento, as ações e as alocações só são lidos.
--
-- ORDEM DE LIGAR (spec R9.14): depois da 20261112100300. Aplicar sozinha não muda nada: os modos ficam como estiverem (desligados até o dado 20261112100990,
-- que também grava marcacoes_desde). O task-automations chama a rodada antes da rodada comunicar (R9.5-21); o código publicado antes da migration pula calado.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7g_correcoes.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261112100400
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; pelo publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261112100400_agenda_fase7g_correcoes.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261112100400', 'agenda_fase7g_correcoes');"
--
-- DESFAZER (com os 3 modos desligados; as linhas gravadas em agenda_marcacoes e agenda_tipos_os ficam, como registro):
--   drop function if exists public.agenda_explicar_rodar(date, timestamptz), public._agenda_explicar_tipos(date, timestamptz),
--     public._agenda_explicar_marcacoes(date, timestamptz), public._agenda_marcacao_desfecho(uuid, uuid, date);
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. O desfecho de uma marcação do gestor ─────────────────────────────────────────────────────────
-- §3.1 item 7 com o R9.4-2 e o R9.3-1. A ordem é a da spec: a 1ª que vale decide. As janelas são "depois da marcação e antes do 1º dia dela" (a 1ª hora,
-- primeiro_inicio). O histórico de os_planejamento tem 4 formas (R9.4-2): a do *grava* (_agenda_aplicar_planejar: {em (dia), autor, trecho, antes, depois},
-- sem por), a do gestor (_agenda_gestor_gravar_dias: {em, quando, autor, por, …}) e as 2 do *desfaz* (agenda_desfazer: {em, quando, por: dono, motivo:
-- desfeito, …} e {em (com hora), por: dono, trecho: desfeito, …}). Conta a entrada com por nulo ou dono, sem a saída do dono (depois.vies_dono_fixo = true,
-- R9.3-1: repetir os dias ou dizer o número corrigido não é correção), com dias, equipe, dupla_dita ou dupla_meios diferente de antes. A hora: quando, senão
-- em (com hora: o instante; só o dia: o dia em Brasília). No mesmo dia da marcação, só o dia não diz se foi antes ou depois: conta só com a hora gravada na
-- linha (estimativa_em para os dias, dupla_em para a dupla, a equipe pela hora da linha mais nova de os_planejamento_equipe) na marcação ou depois — o *grava*
-- que fez o gestor marcar não é correção da marcação.
create or replace function public._agenda_marcacao_desfecho(p_acao uuid, p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_tz     constant text := 'America/Sao_Paulo';
  cf       public.agenda_config := public._agenda_cfg();
  m        public.agenda_marcacoes;
  a        public.agenda_acoes;
  v_alocs  uuid[];
  v_conf   boolean;
  v_dia_m  date;
  v_dia_1  date;
  v_pl     public.os_planejamento;
  v_eq_em  timestamptz;
  v_aj     text[] := '{}';
  v_em     timestamptz;
  v_acao   uuid;
  v_x      record;
  e        jsonb;
  v_q      text;
  v_t      timestamptz;
  v_d      date;
  v_k      text;
  v_ok     boolean;
begin
  select * into m from public.agenda_marcacoes x where x.acao_id = p_acao and x.service_order_id = p_os;
  if not found or m.quem is distinct from 'gestor' then
    return null;  -- a do dono não tem desfecho
  end if;
  select * into a from public.agenda_acoes x where x.id = p_acao;
  -- os meios-dias da marcação: os que a ação criou nesta OS, de turno e sem reserva (os mesmos que a rodada contou)
  v_alocs := array(select al.id from public.agenda_alocacoes al
                    where al.id = any (a.alocacoes_criadas) and al.service_order_id = p_os and al.tipo <> 'reserva' and al.presenca = 'turno');
  v_conf := exists (select 1 from public.agenda_alocacoes al where al.id = any (v_alocs) and al.resultado in ('cumprido', 'parcial'));
  v_dia_m := (m.marcada_em at time zone c_tz)::date;
  v_dia_1 := (m.primeiro_inicio at time zone c_tz)::date;

  -- 1. desfeita
  if a.desfeita_pela is not null then
    select d.id, d.origem, d.criada_em into v_x from public.agenda_acoes d where d.id = a.desfeita_pela;
    if v_x.origem not in ('motor', 'vigia', 'cliente') then
      return jsonb_build_object('desfecho', 'desfeita', 'ajustes', '[]'::jsonb, 'desfecho_em', coalesce(a.desfeita_em, v_x.criada_em),
                                'desfecho_acao_id', v_x.id, 'conferida', v_conf);
    end if;
  end if;

  -- 2. ajustada. (a) a ação do dono na OS: o que mudou pelo degrau dela (P2), senão pelo tipo; fixar sem degrau é fixar no mesmo lugar (não é correção).
  --    least ignora nulo: aqui é o que se quer (v_em começa nulo e fica a hora mais cedo).
  for v_x in
    select x.id, x.tipo, x.degrau, x.criada_em from public.agenda_acoes x
     where (x.service_order_id = p_os or p_os = any (x.os_ids)) and x.executada and x.id <> p_acao
       and x.origem = any (cf.origens_do_dono) and x.tipo in ('criar', 'mover', 'cancelar', 'fixar')
       and x.criada_em >= m.marcada_em and x.criada_em < m.primeiro_inicio
     order by x.criada_em, x.id
  loop
    v_k := case when v_x.degrau = 'pessoa' then 'pessoa'
                when v_x.degrau = 'tirou' then 'tirou'
                when v_x.degrau in ('turno', 'dia', 'data') then 'dia'
                when v_x.tipo = 'cancelar' then 'tirou'
                when v_x.tipo = 'fixar' then null
                else 'dia' end;
    continue when v_k is null;
    v_aj := v_aj || v_k;
    v_em := least(v_em, v_x.criada_em);
    v_acao := coalesce(v_acao, v_x.id);
  end loop;
  -- (b) o histórico de os_planejamento (OS sem linha: o caso comum, nada a ler)
  select * into v_pl from public.os_planejamento x where x.service_order_id = p_os;
  if found then
    select max(q.criado_em) into v_eq_em from public.os_planejamento_equipe q where q.service_order_id = p_os;
    for e in select h.v from jsonb_array_elements(case when jsonb_typeof(v_pl.historico) = 'array' then v_pl.historico else '[]'::jsonb end) as h(v) loop
      continue when jsonb_typeof(e) is distinct from 'object' or jsonb_typeof(e -> 'depois') is distinct from 'object';
      continue when coalesce(e ->> 'por', 'dono') <> 'dono';
      continue when (e -> 'depois' ->> 'vies_dono_fixo') = 'true';
      v_q := coalesce(e ->> 'quando', e ->> 'em');
      v_t := null;
      v_d := null;
      begin
        if v_q ~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}' then
          v_t := v_q::timestamptz;
        elsif v_q ~ '^\d{4}-\d{2}-\d{2}$' then
          v_d := v_q::date;
        end if;
      exception when others then
        v_t := null;
        v_d := null;
      end;
      continue when v_t is null and v_d is null;
      foreach v_k in array array['dias', 'equipe', 'dupla_dita', 'dupla_meios'] loop
        continue when not ((e -> 'depois') ? v_k);
        continue when (e -> 'depois' -> v_k) is not distinct from (e -> 'antes' -> v_k);
        v_ok := case when v_t is not null then v_t >= m.marcada_em and v_t < m.primeiro_inicio
                     else v_d < v_dia_1
                          and (v_d > v_dia_m
                               or (v_d = v_dia_m and case v_k when 'dias' then v_pl.estimativa_em >= m.marcada_em
                                                              when 'equipe' then v_eq_em >= m.marcada_em
                                                              else v_pl.dupla_em >= m.marcada_em end)) end;
        if coalesce(v_ok, false) then
          v_aj := v_aj || case when v_k = 'dias' then 'duracao' else 'pessoa' end;
          v_em := least(v_em, coalesce(v_t, greatest(v_d::timestamp at time zone c_tz, m.marcada_em)));
        end if;
      end loop;
    end loop;
  end if;
  -- (c) o material da OS que o dono mudou (fonte dono), no intervalo
  select min(x.atualizado_em) into v_t from public.os_material x
   where x.service_order_id = p_os and x.fonte = 'dono' and x.atualizado_em >= m.marcada_em and x.atualizado_em < m.primeiro_inicio;
  if v_t is not null then
    v_aj := v_aj || 'material'::text;
    v_em := least(v_em, v_t);
  end if;
  if cardinality(v_aj) > 0 then
    return jsonb_build_object('desfecho', 'ajustada',
             'ajustes', to_jsonb(array(select u.k from unnest(array['duracao', 'pessoa', 'dia', 'tirou', 'material']) with ordinality u(k, o)
                                        where u.k = any (v_aj) order by u.o)),
             'desfecho_em', v_em, 'desfecho_acao_id', v_acao, 'conferida', v_conf);
  end if;

  -- 3. remarcada: quem não é o dono (o gestor; o cliente, R9.4-2) tirou meio-dia desta marcação antes do 1º dia; a nova, se houver, é outra linha
  select x.id, x.criada_em into v_x from public.agenda_acoes x
   where x.executada and x.id <> p_acao and x.alocacoes_canceladas && v_alocs and x.origem <> all (cf.origens_do_dono)
     and x.criada_em >= m.marcada_em and x.criada_em < m.primeiro_inicio
     and not exists (select 1 from public.agenda_alocacoes al
                      where al.id = any (v_alocs) and al.id = any (x.alocacoes_canceladas) and al.cancelada_motivo = 'os_saiu')
   order by x.criada_em, x.id
   limit 1;
  if found then
    return jsonb_build_object('desfecho', 'remarcada', 'ajustes', '[]'::jsonb, 'desfecho_em', v_x.criada_em, 'desfecho_acao_id', v_x.id, 'conferida', v_conf);
  end if;

  -- 4. saiu: a OS saiu da carteira antes do 1º dia (não por ação do dono: essa já foi ajustada)
  select min(al.cancelada_em) into v_t from public.agenda_alocacoes al
   where al.id = any (v_alocs) and al.estado = 'cancelada' and al.cancelada_motivo = 'os_saiu' and al.cancelada_em < m.primeiro_inicio;
  if v_t is not null then
    return jsonb_build_object('desfecho', 'saiu', 'ajustes', '[]'::jsonb, 'desfecho_em', v_t, 'desfecho_acao_id', null, 'conferida', v_conf);
  end if;

  -- 5. aceita: chegou o 1º dia sem nada disso
  if p_hoje >= v_dia_1 then
    return jsonb_build_object('desfecho', 'aceita', 'ajustes', '[]'::jsonb, 'desfecho_em', m.primeiro_inicio, 'desfecho_acao_id', null, 'conferida', v_conf);
  end if;
  -- 6. aberta; depois de correcao_janela_du dias úteis sem 1º dia, aceita (a hora: o começo desse dia em Brasília)
  v_d := public.agenda_somar_du(v_dia_m, cf.correcao_janela_du);
  if p_hoje >= v_d then
    return jsonb_build_object('desfecho', 'aceita', 'ajustes', '[]'::jsonb, 'desfecho_em', v_d::timestamp at time zone c_tz, 'desfecho_acao_id', null,
                              'conferida', v_conf);
  end if;
  return jsonb_build_object('desfecho', 'aberta', 'ajustes', '[]'::jsonb, 'desfecho_em', null, 'desfecho_acao_id', null, 'conferida', v_conf);
end;
$function$;

comment on function public._agenda_marcacao_desfecho(uuid, uuid, date) is
  'Agenda de Produção (Fase 7g, P5; §3.1 item 7, R9.4-2, R9.3-1): o desfecho da marcação do gestor (acao, OS) — {desfecho, ajustes, desfecho_em, desfecho_acao_id, conferida}; nula para a do dono e a que não existe. Na ordem: desfeita (a ação desfeita por quem não é motor, vigia nem cliente); ajustada (entre a marcação e a 1ª hora dela: ação executada do dono na OS — criar, mover, cancelar, ou fixar que mudou o lugar: o ajuste pelo degrau da ação, senão pelo tipo —; o histórico de os_planejamento com por nulo ou dono, sem a saída do dono (depois.vies_dono_fixo), com dias (duracao), equipe, dupla_dita ou dupla_meios (pessoa) diferentes de antes, na hora de quando/em (só o dia: o dia em Brasília; no dia da marcação, só com estimativa_em, dupla_em ou a equipe gravada na marcação ou depois); material da OS com fonte dono (material)); remarcada (ação executada de quem não é o dono que cancelou meio-dia dela antes do 1º dia, menos os_saiu); saiu (meio-dia cancelado por os_saiu antes do 1º dia); aceita (p_hoje no 1º dia ou depois; ou correcao_janela_du dias úteis depois do dia da marcação); senão aberta. conferida = algum meio-dia dela (de turno, sem reserva) com resultado cumprido ou parcial agora. Só lê. Invoker, só service_role.';

-- ── 2. A rodada das marcações: registrar e decidir ──────────────────────────────────────────────────
create or replace function public._agenda_explicar_marcacoes(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_reg  int := 0;
  v_dec  jsonb := '{}'::jsonb;
  v_d    jsonb;
  v_des  text;
  r      record;
begin
  if cf.modo_porque = 'desligado' then
    return jsonb_build_object('modo', 'desligado');
  end if;
  -- (1) registrar. Sem marcacoes_desde, nada (R9.4-2: o plano de antes da 7g não vira aceite no placar). A do dono nasce sem desfecho; a do gestor, aberta.
  if cf.marcacoes_desde is not null then
    insert into public.agenda_marcacoes (acao_id, service_order_id, quem, origem_acao, tipo_acao, classe, duracao_fonte, suposicoes, de, ate, meios, pessoas,
                                         marcada_em, primeiro_inicio, aprovada_em, zona, degrau, desfecho)
    select g.acao_id, g.os, g.quem, g.origem, g.tipo, g.classe, g.fonte,
           array(select s.e ->> 'codigo' from jsonb_array_elements(case when jsonb_typeof(g.sup) = 'array' then g.sup else '[]'::jsonb end) with ordinality s(e, o)
                  order by s.o),
           g.de, g.ate, g.meios, g.pessoas, g.criada_em, g.primeiro, g.aprovada_em, g.zona, g.degrau,
           case when g.quem = 'gestor' then 'aberta' end
      from (select a.id as acao_id, al.service_order_id as os, a.origem, a.tipo, a.criada_em, a.zona, a.degrau,
                   public._agenda_quem_marcou(a.origem, case when bool_or(al.origem = 'dono') then 'dono' end) as quem,
                   public._agenda_classe_de_campo(al.service_order_id) ->> 'chave' as classe,
                   (array_agg(al.duracao_fonte order by lower(al.periodo), al.id))[1] as fonte,
                   (array_agg(al.suposicoes order by lower(al.periodo), al.id))[1] as sup,
                   min(al.dia) as de, max(al.dia) as ate, count(distinct (al.dia, al.turno))::smallint as meios,
                   array_agg(distinct al.payee_id order by al.payee_id) as pessoas, min(lower(al.periodo)) as primeiro,
                   (select coalesce(so.converted_to_os_at, so.signed_at, so.created_at) from public.service_orders so where so.id = al.service_order_id) as aprovada_em
              from public.agenda_acoes a
              join public.agenda_alocacoes al on al.id = any (a.alocacoes_criadas)
             where a.executada and a.criada_em >= cf.marcacoes_desde and a.criada_em <= p_agora
               and a.tipo in ('publicar', 'criar', 'mover', 'promover_reserva', 'fixar', 'reparar', 'reestimar')
               and a.origem <> 'cliente'
               and al.tipo <> 'reserva' and al.presenca = 'turno'
               and not exists (select 1 from public.agenda_marcacoes mm where mm.acao_id = a.id and mm.service_order_id = al.service_order_id)
             group by a.id, al.service_order_id
            having not bool_or(al.origem = 'cliente')) g
     where g.classe is not null
    on conflict (acao_id, service_order_id) do nothing;
    get diagnostics v_reg = row_count;
  end if;
  -- (2) decidir as abertas do gestor (uma vez: decidida não volta, o gatilho da tabela garante)
  for r in select x.acao_id, x.service_order_id from public.agenda_marcacoes x where x.desfecho = 'aberta' order by x.marcada_em, x.acao_id loop
    v_d := public._agenda_marcacao_desfecho(r.acao_id, r.service_order_id, p_hoje);
    v_des := v_d ->> 'desfecho';
    continue when v_des is null or v_des = 'aberta';
    update public.agenda_marcacoes x
       set desfecho = v_des,
           ajustes = array(select jsonb_array_elements_text(v_d -> 'ajustes')),
           desfecho_em = (v_d ->> 'desfecho_em')::timestamptz,
           desfecho_acao_id = (v_d ->> 'desfecho_acao_id')::uuid,
           conferida = coalesce((v_d ->> 'conferida')::boolean, false),
           versao = x.versao + 1,
           historico = public._os_material_historico(x.historico, jsonb_build_object(
             'em', p_agora, 'antes', jsonb_build_object('desfecho', x.desfecho),
             'depois', jsonb_build_object('desfecho', v_des, 'ajustes', v_d -> 'ajustes', 'conferida', coalesce((v_d ->> 'conferida')::boolean, false))))
     where x.acao_id = r.acao_id and x.service_order_id = r.service_order_id;
    v_dec := v_dec || jsonb_build_object(v_des, coalesce((v_dec ->> v_des)::int, 0) + 1);
  end loop;
  return jsonb_build_object('registradas', v_reg, 'decididas', v_dec);
end;
$function$;

comment on function public._agenda_explicar_marcacoes(date, timestamptz) is
  'Agenda de Produção (Fase 7g, P5; §5.5, R9.4-2): o passo marcacoes da rodada explicar. modo_porque desligado = {modo: desligado}, nada gravado. (1) Com marcacoes_desde (nula = nada; R9.4-2, sem olhar para trás), registra em agenda_marcacoes (on conflict do nothing: 2× = 1×) cada (ação, OS) de ação executada criada entre marcacoes_desde e p_agora, de tipo publicar, criar, mover, promover_reserva, fixar, reparar ou reestimar, de origem que não é cliente, que criou meio-dia de turno sem reserva (sem alocação de origem cliente): quem (_agenda_quem_marcou: dono pela origem da ação ou alocação de origem dono), a classe (_agenda_classe_de_campo.chave), a fonte e os códigos das suposições da 1ª alocação, de, ate, meios (meios-dias distintos), pessoas, marcada_em (a hora da ação), primeiro_inicio, aprovada_em (coalesce(converted_to_os_at, signed_at, created_at), R9.5-7), zona e degrau da ação; desfecho aberta na do gestor, nulo na do dono. (2) Decide as abertas por _agenda_marcacao_desfecho (versão + 1 e o histórico). {registradas, decididas: {desfecho: n}}. Invoker, só service_role (quem chama é agenda_explicar_rodar).';

-- ── 3. O tipo de OS: só o que o rebaixar faria ──────────────────────────────────────────────────────
-- §3.1 item 8 com o R9.4-4: o P5 grava só teria, a amostra, os números e o texto. O nível (nivel, desde, a ação nivel, o espera_ok_desde das OS) é do P5b.
-- (ajustada + desfeita) ÷ n só com n > 0 (R9.12-2). As perguntas ok_marcacao respondidas "não" (que a §3.1-8 soma à amostra) não existem antes do P5b.
create or replace function public._agenda_explicar_tipos(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  r         record;
  v_old     public.agenda_tipos_os;
  v_amostra jsonb;
  v_n       int;
  v_corr    int;
  v_seg     int;
  v_teria   text;
  v_txt     text;
  v_cls     int := 0;
  v_esp     int := 0;
begin
  if cf.modo_rebaixar = 'desligado' then
    return jsonb_build_object('modo', 'desligado');
  end if;
  for r in select x.classe, (array_agg(x.service_order_id order by x.marcada_em desc, x.acao_id desc))[1] as os
             from public.agenda_marcacoes x where x.quem = 'gestor' group by x.classe order by x.classe loop
    select coalesce(jsonb_agg(jsonb_build_object('os', s.service_order_id, 'acao', s.acao_id, 'desfecho', s.desfecho, 'em', s.desfecho_em)
                              order by s.desfecho_em desc, s.acao_id desc), '[]'::jsonb),
           count(*), count(*) filter (where s.desfecho in ('ajustada', 'desfeita'))
      into v_amostra, v_n, v_corr
      from (select x.service_order_id, x.acao_id, x.desfecho, x.desfecho_em
              from public.agenda_marcacoes x
             where x.quem = 'gestor' and x.classe = r.classe and x.desfecho in ('aceita', 'ajustada', 'desfeita')
               and x.desfecho_em <= p_agora and x.desfecho_em >= p_agora - make_interval(weeks => cf.rebaixar_janela_semanas)
             order by x.desfecho_em desc, x.acao_id desc
             limit cf.rebaixar_amostra) s;
    -- as aceitas seguidas, da mais nova para trás
    v_seg := coalesce((select min(t.o) - 1 from jsonb_array_elements(v_amostra) with ordinality t(e, o) where t.e ->> 'desfecho' <> 'aceita'),
                      jsonb_array_length(v_amostra));
    select * into v_old from public.agenda_tipos_os t where t.classe = r.classe;
    v_teria := case when v_old.travado_ate is not null and v_old.travado_ate >= p_hoje then 'sozinho'
                    when v_n > 0 and v_n >= cf.rebaixar_n_min and v_corr::numeric / v_n >= cf.rebaixar_taxa then 'espera_ok'
                    else 'sozinho' end;
    v_txt := case when v_teria = 'espera_ok'
                  then left(format('Em teste: nas OS de %s eu passaria a esperar o seu ok (você corrigiu %s de %s).',
                                   coalesce(public._agenda_classe_de_campo(r.os) ->> 'texto', r.classe), v_corr, v_n), 300) end;
    insert into public.agenda_tipos_os as t (classe, teria, n, corrigidas, aceitas_seguidas, amostra, calculado_em, texto, historico)
    values (r.classe, v_teria, v_n, v_corr, v_seg, v_amostra, p_agora, v_txt,
            jsonb_build_array(jsonb_build_object('em', p_agora, 'antes', null, 'depois', jsonb_build_object('teria', v_teria, 'n', v_n, 'corrigidas', v_corr))))
    on conflict (classe) do update
       set teria = excluded.teria, n = excluded.n, corrigidas = excluded.corrigidas, aceitas_seguidas = excluded.aceitas_seguidas,
           amostra = excluded.amostra, calculado_em = excluded.calculado_em, texto = excluded.texto,
           historico = case when t.teria is distinct from excluded.teria
                            then public._os_material_historico(t.historico, jsonb_build_object(
                                   'em', p_agora, 'antes', jsonb_build_object('teria', t.teria, 'n', t.n, 'corrigidas', t.corrigidas),
                                   'depois', jsonb_build_object('teria', excluded.teria, 'n', excluded.n, 'corrigidas', excluded.corrigidas)))
                            else t.historico end
     where (t.teria, t.n, t.corrigidas, t.aceitas_seguidas, t.amostra, t.texto)
           is distinct from (excluded.teria, excluded.n, excluded.corrigidas, excluded.aceitas_seguidas, excluded.amostra, excluded.texto);
    v_cls := v_cls + 1;
    if v_teria = 'espera_ok' then
      v_esp := v_esp + 1;
    end if;
  end loop;
  return jsonb_build_object('classes', v_cls, 'teria', v_esp, 'espera_ok', 0, 'voltaram', 0);
end;
$function$;

comment on function public._agenda_explicar_tipos(date, timestamptz) is
  'Agenda de Produção (Fase 7g, P5; §3.1 item 8, R9.4-4, AG7-25): o passo tipos da rodada explicar. modo_rebaixar desligado = {modo: desligado}, nada gravado. Para cada classe com marcação do gestor: a amostra (as rebaixar_amostra mais novas decididas aceita, ajustada ou desfeita, com desfecho_em nas rebaixar_janela_semanas até p_agora), n, corrigidas (ajustada + desfeita), as aceitas seguidas da mais nova para trás, teria = espera_ok com n > 0, n ≥ rebaixar_n_min e corrigidas ÷ n ≥ rebaixar_taxa, fora da trava (travado_ate ≥ hoje), senão sozinho; texto só com espera_ok ("Em teste: nas OS de <classe> eu passaria a esperar o seu ok (você corrigiu N de M)."). Upsert em agenda_tipos_os só quando algo mudou (2× = 1×); o histórico ganha uma entrada quando teria muda. O nível NÃO muda (é do P5b): em sombra e em ligado, só teria e texto. {classes, teria (quantas teriam espera_ok), espera_ok: 0, voltaram: 0}. Invoker, só service_role.';

-- ── 4. A rodada explicar ────────────────────────────────────────────────────────────────────────────
-- O molde de agenda_aprender (a 7e P7): uma vez por dia, cedo e já rodou são o normal (R9.5-9); o relógio entre os passos e query_canceled por passo
-- (R9.5-8, o molde de agenda_gestor_rodar). Sem linha ociosa: desligado, domingo, cedo, já rodou e nenhum passo a rodar não gravam nada.
create or replace function public.agenda_explicar_rodar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config;
  v_uid    uuid := auth.uid();
  v_t0     timestamptz := clock_timestamp();
  v_passos text[];
  v_passo  text;
  v_r      jsonb;
  v_cont   jsonb := '{}'::jsonb;
  v_erros  int := 0;
  v_falhas jsonb := '[]'::jsonb;
  v_parou  text;
  v_estado text;
  v_msg    text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada explicar.' using errcode = '22023';
  end if;
  -- Quem roda: sem login, o service_role (o task-automations); com login, só administrador e financeiro.
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  cf := public._agenda_cfg();
  if cf.modo_porque = 'desligado' and cf.modo_rebaixar = 'desligado' and cf.modo_placar = 'desligado' then
    return jsonb_build_object('rodou', false, 'desligado', true);
  end if;
  if extract(isodow from p_hoje)::int = 7 then
    return jsonb_build_object('rodou', false, 'domingo', true);
  end if;
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.explicar_hora then
    return jsonb_build_object('rodou', false, 'cedo', true, 'hora', cf.explicar_hora);
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_explicar_rodar'));
  if exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'explicar' and x.p_hoje = p_hoje) then
    return jsonb_build_object('rodou', false, 'ja_rodou', true);
  end if;
  -- os passos de hoje: o placar é do P6 (sem a função, não entra)
  v_passos := case when cf.modo_porque <> 'desligado' then array['marcacoes'] else '{}'::text[] end
           || case when cf.modo_rebaixar <> 'desligado' then array['tipos'] else '{}'::text[] end
           || case when cf.modo_placar <> 'desligado' and extract(isodow from p_hoje)::int = cf.dia_do_plano
                        and to_regprocedure('public._agenda_explicar_placar(date, timestamp with time zone)') is not null
                   then array['placar'] else '{}'::text[] end;
  if cardinality(v_passos) = 0 then
    return jsonb_build_object('rodou', false, 'nada', true);
  end if;
  foreach v_passo in array v_passos loop
    if clock_timestamp() - v_t0 > cf.explicar_tempo_max then
      v_parou := v_passo;
      exit;
    end if;
    begin
      execute format('select public.%I($1, $2)', '_agenda_explicar_' || v_passo) into v_r using p_hoje, p_agora;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception
      -- when others não pega query_canceled (o corte de 30 s do service_role): registra, grava a rodada com parou_no e encerra; o tique seguinte não repete
      when query_canceled then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_parou := v_passo;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('explicar, passo %s: o tempo da rodada acabou (%s)', v_passo, v_msg), 'agenda',
                                     'explicar:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora,
                                                        'tempo_max', cf.explicar_tempo_max::text));
        exit;
      when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('explicar, passo %s: %s', v_passo, v_msg), 'agenda',
                                     'explicar:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;
  v_cont := v_cont || jsonb_build_object('modos', jsonb_build_object('porque', cf.modo_porque, 'rebaixar', cf.modo_rebaixar, 'placar', cf.modo_placar),
                                         'falhas', v_falhas)
            || case when v_parou is not null then jsonb_build_object('parou_no', v_parou) else '{}'::jsonb end;
  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia, v_cont, least(v_erros, 32767),
          greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int), 'explicar', cf.modo_equipe, cf.modo_diaria);
  return jsonb_build_object('rodou', true, 'diaria', true, 'contagens', v_cont - 'falhas' - 'modos' - 'parou_no', 'modos', v_cont -> 'modos',
                            'erros', v_erros, 'falhas', v_falhas)
         || case when v_parou is not null then jsonb_build_object('parou_no', v_parou) else '{}'::jsonb end;
end;
$function$;

comment on function public.agenda_explicar_rodar(date, timestamptz) is
  'Agenda de Produção (Fase 7g, P5; §5.5, R9.5-8, R9.5-9, R9.5-21): a rodada explicar, pelo task-automations a cada tique (agenda-explicar.ts, antes da rodada comunicar). modo_porque, modo_rebaixar e modo_placar desligados = {rodou: false, desligado}; domingo = {rodou: false, domingo}; antes de explicar_hora = {rodou: false, cedo, hora}; a rodada de hoje já gravada = {rodou: false, ja_rodou}; nenhum passo a rodar = {rodou: false, nada}: nenhuma dessas grava linha. Passos, cada um no seu bloco: marcacoes (modo_porque fora de desligado; _agenda_explicar_marcacoes), tipos (modo_rebaixar fora de desligado; _agenda_explicar_tipos) e, no dia_do_plano, placar (modo_placar fora de desligado e _agenda_explicar_placar existindo, do P6). O relógio explicar_tempo_max antes de cada passo: passou, a rodada grava parou_no e o resto fica para amanhã. Erro de um passo → app_error_logs (agenda, explicar:<passo>) e segue; query_canceled → app_error_logs, parou_no e encerra (a linha do dia fica: o tique seguinte não repete). Uma linha em agenda_vigia_rodadas (rotina explicar; contagens: os passos, modos, falhas e parou_no). {rodou: true, diaria, contagens, modos, erros, falhas, parou_no}. Nenhuma mensagem. SECURITY DEFINER; sem login, o service_role; com login, só admin/financeiro (42501). Só service_role tem execute.';

-- ── 5. As portas ────────────────────────────────────────────────────────────────────────────────────
-- Nenhuma leitura de tela chama estas: a rodada é do task-automations (service_role) e as 3 de dentro só ela chama (definer: roda como o dono). Nunca anon nem
-- authenticated.
revoke all on function public.agenda_explicar_rodar(date, timestamptz), public._agenda_explicar_tipos(date, timestamptz),
  public._agenda_explicar_marcacoes(date, timestamptz), public._agenda_marcacao_desfecho(uuid, uuid, date) from public, anon, authenticated;
grant execute on function public.agenda_explicar_rodar(date, timestamptz), public._agenda_explicar_tipos(date, timestamptz),
  public._agenda_explicar_marcacoes(date, timestamptz), public._agenda_marcacao_desfecho(uuid, uuid, date) to service_role;
