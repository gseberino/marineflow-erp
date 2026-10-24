-- Agenda de Produção, Fase 2 ("O gestor de agenda"), pacote P2: o motor determinístico — propor, validar, aplicar,
-- desfazer, marcar e decidir.
-- Spec: scratchpad agenda-pesquisa/spec-fase2.md (§6; §3.1, §3.2, §3.3). Plano: plano-final.md §4.4–§4.7; decisões 23/10
-- (Autonomia). Depende de 20261025100000 (tabelas e invariantes) e 20261025100100 (porta e espelho) e da Fase 1 inteira.
--
-- ═══ DDL — OK NOMEADO ═══ (funções novas e o create or replace de os_prontidao, mesma assinatura e ACL; não grava dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: com a Fase 2 o sistema monta, publica e ajusta a agenda sozinho. Quem decide QUEM vai, EM QUE meio-dia e EM
-- QUE OS é este motor, no banco, sempre do mesmo jeito (mesma entrada, mesma saída byte a byte): o modelo de linguagem
-- nunca escolhe dia nem pessoa, e nada crítico é executado sem a resposta do dono.
--
-- O QUE MUDA:
--   1. os_prontidao recriada com o corpo da Fase 1 (160400) e 4 pontos marcados "-- FASE 2:": a evidência de que a OS
--      andou (_agenda_ultima_evidencia: diária, meio-dia cumprido/parcial, check-in); "parada" só sem dia no plano de
--      hoje em diante; os estados fixada e programada antes de marcada (marcada só fora de 'ligado'); a saída plano
--      (_agenda_plano_da_os) e ultima_evidencia. Sem alocação nenhuma, tudo sai como na Fase 1.
--   2. agenda_meios_da_os: o molde dos meios-dias do que o dono disse (dias × turnos, quem por turno, a presença dele:
--      o que ele disse → ele na equipe dita = turno → a regra d05) e quanto ainda falta (cumprido e sem registro contam
--      1, parcial 0,5).
--   3. agenda_grade: a capacidade (agenda_capacidade) menos o que o plano vigente ocupa; as pontas (abrir/fechar) do
--      dono em dia útil mesmo sem padrão; o compromisso com hora do dono ocupa a ponta.
--   4. _agenda_classe_da_os: 1 em execução/fixada; 2 pronta (dias ditos, sinal, material A/B/C); 3 só reserva
--      condicionada (compra, material, conferir o material, dias só sugeridos); 4 nunca (com quem trava).
--   5. O encaixe, em funções pequenas: _agenda_contexto (a grade em arrays), _agenda_tentar_bloco (um início),
--      _agenda_ocupar (grava um bloco na grade), _agenda_encaixar (a fila inteira, compromisso e reservas).
--   6. agenda_propor (semana | os | replano; restrições fixar, tirar, so_depois_de, atrasar, aceitar_atraso,
--      acima_da_carga; persistir): estabilidade (o publicado não violado nunca muda), congelamento (hoje + o próximo
--      dia útil; só o evento real replaneja ali), a fila por classe, o encaixe multi-dia com no máximo 1 interrupção,
--      ≤ 2 frentes por meio-dia, teto de 80% por pessoa e semana, a sobrecarga (Moore-Hodgson) que vira a pergunta
--      crítica nao_cabe com as opções e a recomendação, reservas (teto, condicionada com data-limite, pátio), o diff e
--      os textos prontos. Toda proposta passa pela agenda_validar antes de sair: inválida nunca sai.
--   7. agenda_validar (14 regras duras), agenda_aplicar (só em 'ligado'), agenda_descartar, agenda_desfazer (24 h e
--      antes de começar), agenda_acao_desfazivel, agenda_marcar_os (tela, aprovação e o *grava*), agenda_decidir (a
--      resposta do dono executa o efeito com critica = true), agenda_os_do_dia e _agenda_criticidade (a regra única do
--      que é crítico, a mesma que a agenda_saude reconfere).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase2_motor.sql):
--   · desejado sem equipe dita: a sugestão diz quantas pessoas no TOTAL ("1 pessoa"); quando o dono fica o turno
--     inteiro ele é uma delas (o diagnóstico do Rodrigo é "você", não "você e mais um"). desejado = pessoas − 1 nos
--     turnos em que o dono está.
--   · meio-dia passado sem resultado (ainda não virou sem_registro) conta como feito, igual ao sem_registro (d20): sem
--     isso o motor marcaria de novo o que talvez já foi feito.
--   · OS com alocação violada: além da violada, saem o resto do mesmo meio-dia (o meio-dia está quebrado) e os
--     meios-dias publicados dela depois do congelado — o que sobra volta à fila como um bloco só (sem isso a OS ficaria
--     picada). Os de hoje e amanhã não violados ficam; o fixado pelo dono só sai quando é impossível.
--   · evento real (d10): além da OS da classe 1, vale para a OS que perdeu um meio-dia DENTRO do congelado (hoje ou
--     amanhã): ela pode usar meio-dia livre ainda não começado do congelado — nunca o de outra OS.
--   · a classe sai das restrições da prontidão, não do estado: uma OS programada com o material atrasado continua
--     "programada" no estado, mas é classe 4 para o motor (e a alocação é violada).
--   · fixar (pedido do dono pela tela, aprovação ou *grava*) pode usar hoje ainda não começado e amanhã, usa o teto de
--     100% e aceita a duração só sugerida (aplicar grava "aceita"); orçamento, sinal, cliente, espera e material
--     atrasado continuam recusando ("Não cabe … : …").
--   · nao_cabe: X sai da proposta e vai para fora com a pergunta; as OS que X empurraria (as da classe 2 colocadas antes
--     dela, as 3 mais próximas) ficam na proposta como itens críticos que só entram com a resposta (§3.2: "o encaixe
--     dela e o das que ela empurraria"). As opções são simuladas sobre a grade JÁ com o resto publicado, que é o que a
--     decisão vai encontrar. Sem nenhuma opção que faça X caber, a 2ª opção é "deixo X fora do plano por enquanto".
--   · o atraso crítico de quem já tinha plano (atraso_longo, segundo_atraso, remarcar_confirmado, fixada_pelo_dono):
--     o cancelamento do que não pode mais acontecer é aplicado (fato); o novo encaixe fica crítico, com as opções
--     "sigo assim" e "deixo fora até você decidir" (recomendação: seguir e ligar para o cliente).
--   · agenda_validar ganha p_pergunta (opcional, no fim): escolhe os itens como o agenda_aplicar (os não críticos e os
--     críticos decididos por ela). _agenda_criticidade ganha p_cancela/p_violadas (opcionais): a regra 3 precisa saber
--     que alocação o item cancela.
--   · a pergunta crítica do motor nasce com o modo da PROPOSTA (o plano é dela); as da vigia (P3) usam o modo_vigia.
--   · agenda_aplicar fora de 'ligado' não grava nada (nem ação em sombra): a vigia (P3) registra o que faria.
--   · agenda_desfazer de "a semana": agenda_acao_desfazivel('semana') devolve todas as ações publicar daquela
--     proposta (acao_ids); agenda_desfazer desfaz uma por vez.
--   · propostas e alocações do motor gravam criada_em = p_agora (a proposta expira em p_agora + validade; com o relógio
--     do banco, um teste com p_agora no passado nasceria vencida).
--   · o compromisso também respeita os 100% da semana (compromisso + reserva): com uma reserva já em vigor, um
--     compromisso novo dentro dos 80% passaria da semana inteira da pessoa (a validação, regra 6, pegou no ensaio).
--   · quem espera a decisão sai da MESMA rodada (as reservas são postas depois de todos os compromissos e não tomam o
--     lugar deles); X (a que não cabe) não é publicada e o encaixe tardio dela não vira item.
--   · a parada usa a evidência nova, mas o texto continua o da Fase 1 ("em andamento sem diária desde dd/mm"): a
--     variável e a chave ultima_diaria não mudam.
--   · agenda_desfazer recria o que saiu conferindo só a EXCLUDE (quem já está no lugar recusa o desfazer); a
--     disponibilidade da pessoa não é reconferida: desfazer é a ordem do dono, e ele sabe se o Roberto vem.
--   · a amostra de §13 para a semana de 03 a 06/11 da carteira de 29/10 não sai destas regras: o Nelson pede 2
--     diaristas por meio-dia (a sugestão) e o João só tem 3 meios-dias na semana — ele vira a pergunta nao_cabe sem
--     opção que o faça caber (só "atrasa" e "fica fora"). O P5 fixa os textos sobre o que a função devolve.
--
-- O QUE NÃO MUDA: nenhuma tabela, nenhum dado, nenhum gatilho; a porta e o espelho (100100) só passam a ser chamados.
-- Nenhuma tela nem função de borda chama o motor ainda (P3 a vigia, P4 a tela e o rascunho).
--
-- ORDEM DE LIGAR: depois de 20261025100000 e 100100; antes de 20261025100300 (a vigia chama o motor).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase2_motor.sql (begin/rollback; o cenário à mão da spec §14.2 com
-- as células conferidas, invariantes, estabilidade, congelamento, teto, presença do dono, interrupção, feriados, o
-- replay da OS-00104, sobrecarga, desfazer, determinismo, sombra e o custo). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261025100200
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261025100200_agenda_fase2_motor.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261025100200', 'agenda_fase2_motor');"
--
-- IDEMPOTENTE: só create or replace function, revoke/grant e comment.

-- ── 0. O plano de uma OS, para a prontidão ─────────────────────────────────────────────────────────────

-- A última vez que a OS andou: a maior entre a última diária ligada a ela, o último meio-dia do plano cumprido ou
-- parcial e o dia do check-in (Brasília). null = nunca.
create or replace function public._agenda_ultima_evidencia(p_so_id uuid, p_hoje date)
 returns date
 language sql
 stable
 set search_path to 'public'
as $function$
  select greatest(
    (select max(ws.data) from public.work_shifts ws
      where ws.data <= p_hoje and ws.tipo in ('normal', 'diaria') and coalesce(ws.fracao, 1) > 0
        and (ws.service_order_id = p_so_id
             or exists (select 1 from public.work_shift_os x where x.shift_id = ws.id and x.service_order_id = p_so_id))),
    (select max(a.dia) from public.agenda_alocacoes a
      where a.service_order_id = p_so_id and a.estado in ('publicada', 'fixada') and a.dia <= p_hoje
        and a.resultado in ('cumprido', 'parcial')),
    (select (so.check_in_at at time zone 'America/Sao_Paulo')::date from public.service_orders so
      where so.id = p_so_id and (so.check_in_at at time zone 'America/Sao_Paulo')::date <= p_hoje));
$function$;

comment on function public._agenda_ultima_evidencia(uuid, date) is
  'Agenda de Produção (Fase 2, P2): a última evidência de que a OS andou até p_hoje — a maior entre a última diária ligada (work_shifts/work_shift_os), o último meio-dia vigente com resultado cumprido ou parcial e o dia do check-in (Brasília). null = nunca.';

-- O que o plano vigente diz de uma OS. null = sem alocação vigente nenhuma.
create or replace function public._agenda_plano_da_os(p_so_id uuid, p_hoje date)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with a as (
    select x.* from public.agenda_alocacoes x
     where x.service_order_id = p_so_id and x.estado in ('publicada', 'fixada')
  ),
  -- Um meio-dia da OS (fora a reserva): vale o melhor resultado entre as pessoas (d20: cumprido e sem registro = 1,
  -- parcial = meio, não cumprido = 0; o passado ainda sem resultado conta como feito, como o sem registro).
  meio as (
    select a.dia, a.turno,
           max(case when a.resultado in ('cumprido', 'sem_registro') then 2
                    when a.resultado is null and a.dia < p_hoje then 2
                    when a.resultado = 'parcial' then 1
                    else 0 end) as peso,
           bool_and(a.resultado is null) and min(a.dia) >= p_hoje as futuro
      from a where a.tipo <> 'reserva'
     group by a.dia, a.turno
  ),
  r as (
    select min(a.dia) filter (where a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null) as proximo,
           max(a.dia) filter (where a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido') as ultimo,
           min(a.dia) filter (where a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido') as inicio,
           count(distinct a.dia) filter (where a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido') as dias,
           coalesce(bool_or(a.tipo <> 'reserva' and a.estado = 'fixada' and a.dia >= p_hoje and a.resultado is null), false) as fixada,
           count(*) as n
      from a
  )
  select case when r.n = 0 then null else jsonb_build_object(
    'proximo_dia', r.proximo,
    'ultimo_dia', r.ultimo,
    'inicio', r.inicio,
    'dias', r.dias,
    'meios_vigentes', (select count(*) from meio m where m.futuro),
    'meios_cumpridos', (select trim_scale(coalesce(sum(m.peso), 0)::numeric / 2) from meio m where not m.futuro),
    'fixada', r.fixada,
    'reservas', coalesce((select jsonb_agg(jsonb_build_object('dia', q.dia, 'condicao', q.condicao, 'ate', q.condicao_ate)
                                           order by q.dia)
                            from (select distinct on (a.dia) a.dia, a.condicao, a.condicao_ate from a
                                   where a.tipo = 'reserva' and a.dia >= p_hoje
                                   order by a.dia, a.condicao_ate nulls last, a.id) q), '[]'::jsonb),
    'fim_publicado', r.ultimo,
    'confirmado_cliente', coalesce((select (so.client_confirmed_for at time zone 'America/Sao_Paulo')::date = r.proximo
                                      from public.service_orders so where so.id = p_so_id), false)) end
    from r;
$function$;

comment on function public._agenda_plano_da_os(uuid, date) is
  'Agenda de Produção (Fase 2, P2): o plano vigente de uma OS em p_hoje — {proximo_dia, ultimo_dia (= fim_publicado), inicio, dias, meios_vigentes (meios-dias de hoje em diante sem resultado), meios_cumpridos (d20: cumprido/sem registro/passado sem resultado = 1, parcial = 0,5), fixada (tem meio-dia fixado de hoje em diante), reservas [{dia, condicao, ate}], confirmado_cliente (client_confirmed_for = o próximo dia)}. Reserva não conta como dia; null sem alocação vigente.';

-- ── 1. A prontidão com o plano ─────────────────────────────────────────────────────────────────────────
-- O corpo de 20261024160400 (Fase 1) copiado sem mudar, menos os 4 pontos marcados "-- FASE 2:" (o teste compara o
-- corpo fora deles com o da Fase 1, linha a linha).
create or replace function public.os_prontidao(p_so_id uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c            public.agenda_config := public._agenda_cfg();
  so           record;
  p            public.os_planejamento%rowtype;
  v_na_cart    boolean;
  v_aprov      date;
  v_pago       numeric := 0;
  v_pend       numeric := 0;
  v_ag_de      date;
  v_ag_ate     date;
  v_bem_nome   text;
  v_d_bem      date;
  v_bem_tudo   boolean := false;
  v_horizonte  date;
  v_base       date;
  v_est_sm     date;
  v_bruto      jsonb;
  v_itens      jsonb;
  v_crit       jsonb;
  v_embut      jsonb;
  v_n_itens    int;
  v_conferido  boolean;
  v_mat_estado text;
  v_dpm        date;
  v_gargalo    jsonb;
  v_confianca  text;
  v_inicio_mat date;
  v_est        date;
  v_sug        jsonb;
  v_dur        jsonb;
  v_equipe     jsonb;
  v_meios      numeric;
  v_diarias_eq numeric;
  v_dias_re    numeric;
  v_pres       jsonb;
  v_prazo      date;
  v_prazo_fnt  text;
  v_razao      numeric;
  v_r          jsonb := '[]'::jsonb;
  v_estado     text;
  v_estado_txt text;
  v_principal  jsonb;
  v_quase      boolean := false;
  v_parada     boolean := false;
  v_ult_diaria date;
  v_x          jsonb;
  v_compra     jsonb;
  v_n          int;
  v_n_falta    int := 0;
  v_n_sem      int;
  v_txt        text;
  v_cond       text;
  v_dono_padrao boolean;
  v_cc         record;
  -- FASE 2: o que o plano publicado diz da OS (spec-fase2 §6.1)
  v_plano      jsonb;
  v_ult_evid   date;
  v_tem_futuro boolean := false;
  -- FASE 2: fim
begin
  if p_hoje is null then
    raise exception 'os_prontidao: sem o dia de hoje' using errcode = '22004';
  end if;

  select o.*, cl.name as cliente_nome, vs.name as bem, vs.asset_type as bem_tipo,
         mg.service_order_number as juntado_em
    into so
    from public.service_orders o
    left join public.clients cl on cl.id = o.client_id
    left join public.vessels vs on vs.id = o.vessel_id
    left join public.service_orders mg on mg.id = o.merged_into_id
   where o.id = p_so_id;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;

  select * into p from public.os_planejamento where service_order_id = p_so_id;

  -- Carteira, aprovação, sinal e janela antiga: a MESMA conta de os_carteira (fora dela, a mesma fórmula).
  select true, k.aprovada_em, k.sinal_pago, k.sinal_pendente, k.agendada_de, k.agendada_ate
    into v_na_cart, v_aprov, v_pago, v_pend, v_ag_de, v_ag_ate
    from public.os_carteira(p_hoje) k where k.service_order_id = p_so_id;
  if not found then
    v_na_cart := false;
    v_aprov := (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date;
    select coalesce(sum(coalesce(r.paid_amount, 0)), 0),
           coalesce(sum(case when r.status in ('pending', 'partially_paid', 'overdue')
                             then greatest(r.amount - coalesce(r.paid_amount, 0), 0) else 0 end), 0)
      into v_pago, v_pend
      from public.receivables r
     where r.service_order_id = p_so_id and r.is_deposit and r.status <> 'cancelled';
    v_ag_de := (so.scheduled_start_at at time zone 'America/Sao_Paulo')::date;
    v_ag_ate := (coalesce(so.scheduled_end_at, so.scheduled_start_at) at time zone 'America/Sao_Paulo')::date;
  end if;

  -- O bem (barco, motorhome): 1º dia a partir de amanhã fora de bem_indisponivel; null = fora sem data de volta.
  v_bem_nome := case when public._agenda_normal(coalesce(so.bem_tipo, so.bem)) ~ 'motorhome|motor home|trailer'
                     then 'o motorhome' else 'o barco' end;
  v_horizonte := p_hoje + 7 * c.horizonte_semanas;
  v_d_bem := p_hoje + 1;
  if p.service_order_id is not null and not isempty(p.bem_indisponivel) and p.bem_indisponivel @> v_d_bem then
    select upper(r) into v_d_bem from unnest(p.bem_indisponivel) r where r @> (p_hoje + 1);
  end if;
  v_bem_tudo := v_d_bem is null or v_d_bem > v_horizonte;

  -- O início mais cedo sem olhar o material: o bem livre, o "não antes de" e o congelamento (hoje + o próximo
  -- dia útil ficam como estão).
  v_base := public.agenda_somar_du(p_hoje, c.congelamento_du + 1);
  v_est_sm := greatest(v_d_bem, p.nao_antes_de, v_base);

  -- ── Material efetivo: a conta bruta + o que foi informado em os_material ──
  v_bruto := public.os_necessidade_bruta(p_so_id);

  with
  bruto as (
    select x.ord, x.i ->> 'origin' as origin, (x.i ->> 'sourceId')::uuid as src,
           (x.i ->> 'required')::numeric as req, coalesce((x.i ->> 'available')::numeric, 0) as disp,
           x.i ->> 'status' as st, (x.i ->> 'productId')::uuid as prod, x.i ->> 'description' as descr
      from jsonb_array_elements(coalesce(v_bruto -> 'items', '[]'::jsonb)) with ordinality x(i, ord)
     where coalesce((x.i ->> 'required')::numeric, 0) > 0
       and x.i ->> 'origin' in ('part', 'free_text', 'purchase_order')
  ),
  cand as (
    -- (1) os itens da conta bruta, com a linha do mesmo vínculo
    select 1 as grupo, b.ord::bigint as ord,
           case b.origin when 'part' then 'peca' when 'free_text' then 'texto_livre' else 'oc' end as origem,
           b.src as vinculo, b.req, b.disp, b.st, b.descr, b.prod, null::uuid as po_forn, null::date as recebido_em,
           m as l
      from bruto b
      left join public.os_material m
        on m.service_order_id = p_so_id
       and m.origem = case b.origin when 'part' then 'peca' when 'free_text' then 'texto_livre' else 'oc' end
       and b.src = case m.origem when 'peca' then m.service_order_part_id
                                 when 'texto_livre' then m.service_order_service_id
                                 else m.purchase_order_item_id end
    union all
    -- (2) item de OC de texto livre da OS que já chegou (saiu da conta bruta) — continua, na mão
    select 2, row_number() over (order by po.created_at, poi.id), 'oc', poi.id, poi.quantity, poi.quantity,
           'recebido', poi.description, null, po.supplier_id, po.received_date, m
      from public.purchase_order_items poi
      join public.purchase_orders po on po.id = poi.purchase_order_id
      left join public.os_material m on m.origem = 'oc' and m.purchase_order_item_id = poi.id
     where po.service_order_id = p_so_id and poi.product_id is null and poi.quantity > 0
       and po.status <> 'cancelled'
       and (po.status = 'received' or coalesce(poi.received_qty, 0) >= poi.quantity)
    union all
    -- (3) item de OC cancelada que tinha linha: a sincronização o devolveu a "falta" (ou o dono informou)
    select 3, row_number() over (order by po.created_at, poi.id), 'oc', poi.id, poi.quantity, 0,
           'cancelado', poi.description, null, po.supplier_id, null, m
      from public.os_material m
      join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
      join public.purchase_orders po on po.id = poi.purchase_order_id
     where m.service_order_id = p_so_id and m.origem = 'oc' and po.status = 'cancelled'
    union all
    -- (4) o que o dono citou e não está no orçamento (peça embutida, material novo)
    select 4, row_number() over (order by m.descricao, m.id), 'dono', m.service_order_service_id,
           m.quantidade_necessaria, 0, 'dono', m.descricao, null, null, null, m
      from public.os_material m
     where m.service_order_id = p_so_id and m.origem = 'dono'
  ),
  passo1 as (
    select k.*,
           coalesce((k.l).fonte in ('dono', 'fornecedor', 'nfe', 'pix'), false) as informado,
           coalesce((k.l).critico, true) as critico
      from cand k
     where (k.l).situacao is distinct from 'dispensado'
  ),
  passo2 as (
    select q.*,
           case when q.grupo = 1
                then greatest(q.disp, case when q.informado then least(q.req, (q.l).quantidade_na_mao) else 0 end)
                else 0 end as disp_ef
      from passo1 q
  ),
  passo3 as (
    -- A situação efetiva. Só o fato informado muda o item; "na mão" só com a quantidade completa contra a conta de
    -- hoje; o que o dono disse para menos do que a OS pede hoje volta a faltar.
    select q.*,
           case
             when q.grupo = 2 then case when q.informado and (q.l).situacao <> 'na_mao' then (q.l).situacao else 'na_mao' end
             when q.grupo = 4 then (q.l).situacao
             when q.grupo = 3 then case when q.informado then (q.l).situacao else 'falta' end
             when q.disp_ef >= q.req then 'na_mao'
             when q.informado and (q.l).situacao in ('na_mao', 'comprado', 'a_caminho')
                  and (q.l).quantidade_necessaria < q.req then 'falta'
             when q.informado and (q.l).situacao = 'na_mao' then 'falta'
             when q.informado then (q.l).situacao
             when q.st = 'on_order' then 'a_caminho'
             else 'falta' end as sit
      from passo2 q
  ),
  passo4 as (
    -- A OC que cobre o item que o sistema vê "a caminho" (a da própria OS primeiro): previsão, data e fornecedor.
    select q.*, oc.expected_date as oc_prev, oc.criada as oc_criada, oc.po_number as oc_numero, oc.forn as oc_forn,
           pr.supplier_id as prod_forn
      from passo3 q
      left join public.products pr on pr.id = q.prod
      left join lateral (
        select v.expected_date, (v.po_criada_em at time zone 'America/Sao_Paulo')::date as criada, v.po_number,
               po.supplier_id as forn
          from public.v_oc_itens_a_caminho v
          join public.purchase_orders po on po.id = v.purchase_order_id
         where q.grupo = 1 and q.sit = 'a_caminho' and not q.informado and v.pendente > 0
           and case when q.origem = 'oc' then v.purchase_order_item_id = q.vinculo
                    else v.product_id = q.prod and v.conta_como_ja_pedido end
         order by (v.service_order_id is distinct from p_so_id), v.po_criada_em, v.purchase_order_item_id
         limit 1) oc on true
  ),
  passo5 as (
    select q.*,
           case
             when q.sit = 'na_mao' and q.grupo = 1 and q.disp >= q.req and not q.informado then 'estoque'
             when q.informado then (q.l).fonte
             when q.grupo = 2 then 'oc'
             when q.sit = 'a_caminho' and q.grupo = 1 then 'oc'
             else (q.l).fonte end as fonte,
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado then (q.l).previsao_ate when q.grupo = 1 then q.oc_prev end end as prev_ate,
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado then (q.l).previsao_fonte
                       when q.grupo = 1 and q.oc_prev is not null then 'oc' end end as prev_fonte,
           -- O informado sem data de compra conta do dia em que o dono contou (conferido_em): a estimativa não anda.
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado
                       then coalesce((q.l).comprado_em, ((q.l).conferido_em at time zone 'America/Sao_Paulo')::date)
                       when q.grupo = 1 then q.oc_criada end end as comprado_em,
           case when q.sit = 'falta' and q.informado then (q.l).compra_prevista_em end as compra_prevista_em,
           case when q.sit = 'na_mao' then
                  case when q.informado or q.grupo = 4 then (q.l).chegou_em
                       when q.grupo = 2 then coalesce((q.l).chegou_em, q.recebido_em)
                       when (q.l).situacao = 'na_mao' then (q.l).chegou_em end end as chegou_em,
           -- O fornecedor: o que o dono disse (cadastrado ou só o nome), senão o da OC, senão o do produto.
           case when q.informado and (q.l).fornecedor_id is null and (q.l).fornecedor_nome is not null then null
                else coalesce(case when q.informado then (q.l).fornecedor_id end, q.oc_forn, q.po_forn,
                              (q.l).fornecedor_id, q.prod_forn) end as forn_id,
           case when q.informado and (q.l).fornecedor_id is null then (q.l).fornecedor_nome end as forn_nome
      from passo4 q
  ),
  passo6 as (
    select q.*, public._agenda_classe_do_fornecedor(q.forn_id) as classe
      from passo5 q
  ),
  passo7 as (
    select q.*, public._agenda_prazo_da_classe(q.classe) as prazo
      from passo6 q
  ),
  passo8 as (
    select q.*,
           case
             when q.sit = 'na_mao' then 'A'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null and q.prev_fonte <> 'dono' then 'B'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then 'C'
             when q.sit in ('comprado', 'a_caminho') then 'D'
             when q.prazo is not null then 'D'
             else 'E' end as nivel,
           case
             when q.sit = 'na_mao' then q.chegou_em
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then q.prev_ate
             when q.sit in ('comprado', 'a_caminho') and q.prazo is not null then
               public.agenda_somar_du(coalesce(q.comprado_em, p_hoje), q.prazo)
             when q.sit = 'falta' and q.prazo is not null then
               -- "Se comprar hoje" (ou no dia combinado): calculado, nunca gravado.
               public.agenda_somar_du(greatest(coalesce(q.compra_prevista_em, p_hoje), p_hoje), q.prazo)
           end as data,
           case when q.sit = 'falta' and q.prazo is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(v_est_sm, -(c.folga_material_du + q.prazo)) end as compre_ate,
           (select f.name from public.suppliers f where f.id = q.forn_id) as forn_cadastro
      from passo7 q
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', (q.l).id, 'linha', q.vinculo, 'origem', q.origem,
           'descricao', coalesce((q.l).descricao, q.descr), 'curto', public._agenda_linha_curta(coalesce((q.l).descricao, q.descr)),
           'nivel', q.nivel, 'situacao', q.sit, 'data', q.data,
           -- Parcial (parte já na mão, informada ou do estoque): quantas estão na mão e quantas faltam, antes do resto.
           'data_texto', case when q.sit <> 'na_mao' and q.disp_ef > 0 and q.disp_ef < q.req
                              then format('%s de %s na mão, %s %s: ', replace(trim_scale(q.disp_ef)::text, '.', ','),
                                          replace(trim_scale(q.req)::text, '.', ','),
                                          case when q.req - q.disp_ef = 1 then 'falta' else 'faltam' end,
                                          replace(trim_scale(q.req - q.disp_ef)::text, '.', ','))
                              else '' end
           || case
              when q.nivel = 'A' then case when q.data is not null then 'na mão desde ' || public._dia_curto(q.data) else 'na mão' end
              when q.nivel = 'B' then 'chega ' || public._dia_curto(q.data) || case q.prev_fonte
                   when 'oc' then ' (pela OC)' when 'fornecedor' then ' (o fornecedor disse)'
                   when 'nfe' then ' (pela nota)' when 'pix' then ' (pelo Pix)' else '' end
              when q.nivel = 'C' then 'chega ' || public._dia_curto(q.data) || ' (você disse)'
              when q.sit in ('comprado', 'a_caminho') then
                   coalesce('pedido em ' || to_char(q.comprado_em, 'DD/MM'), 'comprado')
                   || case when q.data is not null then ', deve chegar por volta de ' || public._dia_curto(q.data)
                           else ', sem previsão' end
              when q.nivel = 'D' then
                   case when q.compra_prevista_em is not null and q.compra_prevista_em >= p_hoje
                        then format('comprando %s, chega por volta de %s', public._dia_curto(q.compra_prevista_em),
                                    public._dia_curto(q.data))
                        else 'se comprar hoje, chega por volta de ' || public._dia_curto(q.data) end
              when q.forn_nome is not null then format('a comprar de %s, sem prazo conhecido', q.forn_nome)
              when q.forn_id is not null then format('a comprar de %s, sem cidade/UF no cadastro', public._agenda_nome_curto(q.forn_cadastro))
              else 'a comprar, sem fornecedor' end,
           'fonte', q.fonte, 'previsao_fonte', q.prev_fonte, 'trecho', (q.l).trecho, 'critico', q.critico,
           'quantidade', trim_scale(q.req), 'na_mao', trim_scale(case when q.sit = 'na_mao' then q.req else q.disp_ef end),
           'fornecedor', coalesce(q.forn_nome, public._agenda_nome_curto(q.forn_cadastro)),
           'classe', q.classe, 'prazo_du', q.prazo,
           'comprado_em', q.comprado_em, 'compra_prevista_em', q.compra_prevista_em,
           'compre_ate', q.compre_ate,
           'atrasado', q.sit in ('comprado', 'a_caminho') and q.data is not null and q.data < p_hoje,
           'sem_data', q.nivel = 'E' or (q.nivel = 'D' and q.data is null))
           order by q.grupo, q.ord), '[]'::jsonb)
    into v_itens
    from passo8 q;

  v_crit := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_itens) with ordinality t(e, o)
                       where (e ->> 'critico')::boolean), '[]'::jsonb);
  v_n_itens := jsonb_array_length(v_itens);
  v_conferido := p.material_conferido_em is not null
              or exists (select 1 from public.os_material m
                          where m.service_order_id = p_so_id and m.fonte in ('dono', 'fornecedor', 'nfe', 'pix'));

  -- "Tem peça embutida?": linha de texto livre que NÃO entra na compra e (a) vale >= peca_embutida_acima, ou (b) o
  -- classificador lê como material (a unidade não é 'unit'), ou (c) cita peça/material. Some quando o dono responde
  -- por ela (linha do dono ligada à linha) ou quando ele diz "não tem peça a comprar" depois que a linha nasceu.
  select coalesce(jsonb_agg(jsonb_build_object('linha', s.id, 'nome', s.name_snapshot,
                                               'curto', public._agenda_linha_curta(s.name_snapshot),
                                               'valor', s.line_total)
                            order by s.line_total desc nulls last, s.created_at, s.id), '[]'::jsonb)
    into v_embut
    from public.service_order_services s
   where s.service_order_id = p_so_id and s.service_id is null
     and not (s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0 and public.free_text_is_material(s.name_snapshot))
     and (coalesce(s.line_total, 0) >= c.peca_embutida_acima
          or public.free_text_is_material(s.name_snapshot)
          or public._agenda_normal(s.name_snapshot) ~ '\m(peca|pecas|material)\M')
     and not exists (select 1 from public.os_material m
                      where m.service_order_id = p_so_id and m.origem = 'dono' and m.service_order_service_id = s.id)
     and not (p.material_conferido_em is not null and p.material_conferido_em > s.created_at);

  -- O estado do material (do mais forte ao mais fraco).
  v_mat_estado := case
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'atrasado')::boolean) then 'atrasado'
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'sem_data')::boolean) then 'sem_previsao'
    when jsonb_array_length(v_embut) > 0 or (v_n_itens = 0 and not v_conferido) then 'nao_conferido'
    when exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' <> 'A') then 'previsto'
    else 'completo' end;

  -- DPM: a data mais tarde dos críticos fora de A; o início pelo material = chegada + folga_material_du, sem folga
  -- remota (revisão §7: o prazo "outro estado" já cobre o transporte).
  if v_mat_estado not in ('atrasado', 'sem_previsao') then
    select e into v_gargalo from jsonb_array_elements(v_crit) with ordinality t(e, o)
     where e ->> 'nivel' <> 'A' order by (e ->> 'data')::date desc, o limit 1;
    v_dpm := (v_gargalo ->> 'data')::date;
    if v_dpm is not null then
      v_inicio_mat := public.agenda_somar_du(v_dpm, c.folga_material_du);
    end if;
    v_est := greatest(v_est_sm, v_inicio_mat);
  end if;
  v_confianca := (select e ->> 'nivel' from jsonb_array_elements(v_crit) e
                   order by case e ->> 'nivel' when 'E' then 0 when 'D' then 1 when 'C' then 2 when 'B' then 3 else 4 end
                   limit 1);

  -- ── Duração ──
  v_sug := public.os_duracao_sugerida(p_so_id);
  v_dono_padrao := exists (select 1 from public.agenda_disponibilidade d
                            where d.payee_id = public._agenda_dono(null) and d.substituida_em is null
                              and d.dias_semana is not null and d.situacao = 'disponivel');
  if p.dias is not null then
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                                 'eh_dono', py.kind = 'socio', 'turnos', e.turnos)
                              -- você primeiro; quem vai o dia todo antes de quem vai meio turno
                              order by py.kind = 'socio' desc, e.turnos = 'dia' desc, py.name, e.payee_id), '[]'::jsonb),
           -- Meios-dias por pessoa: o dia todo = 2 por dia; só de manhã ou só à tarde = 1 turno em cada dia que o
           -- serviço ocupa (meio dia com o João à tarde = 1 meio-dia; 1,5 dia à tarde = 2).
           coalesce(sum(case when e.turnos = 'dia' then p.dias * 2 else ceil(p.dias) end), 0)
      into v_equipe, v_meios
      from public.os_planejamento_equipe e
      join public.payees py on py.id = e.payee_id
     where e.service_order_id = p_so_id;
    -- Sem equipe dita, a conta de diárias usa as pessoas da sugestão (é leitura, não vira número gravado). Na conta da
    -- equipe (a que a capacidade cobre), você só entra quando tem padrão.
    v_diarias_eq := case when jsonb_array_length(v_equipe) = 0
                         then p.dias * coalesce((v_sug ->> 'pessoas')::int, 1)
                         else (select coalesce(sum(case when e.turnos = 'dia' then p.dias * 2 else ceil(p.dias) end), 0) / 2
                                 from public.os_planejamento_equipe e join public.payees py on py.id = e.payee_id
                                where e.service_order_id = p_so_id
                                  and (py.kind <> 'socio' or v_dono_padrao)) end;
    v_dur := jsonb_build_object(
      'fonte', p.estimativa_fonte, 'dias', trim_scale(p.dias), 'equipe', v_equipe,
      'meios_dias', trim_scale(v_meios),
      'diarias', trim_scale(case when jsonb_array_length(v_equipe) = 0
                                 then p.dias * coalesce((v_sug ->> 'pessoas')::int, 1)
                                 else v_meios / 2 end),
      'diarias_equipe', trim_scale(v_diarias_eq),
      -- Diárias-pessoa da equipe para o backlog: o que o dono disse é um número só (otimista = realista).
      'dp_otimista', trim_scale(v_diarias_eq), 'dp_realista', trim_scale(v_diarias_eq),
      'equipe_dita', jsonb_array_length(v_equipe) > 0,
      'texto', public._agenda_dias(p.dias)
               || case when jsonb_array_length(v_equipe) > 0 then ': ' || public._agenda_lista(array(
                    select case when (x ->> 'eh_dono')::boolean then 'você' else x ->> 'nome' end
                           || case x ->> 'turnos' when 'dia' then ' (dia todo)' when 'manha' then ' (de manhã)'
                                                  else ' (à tarde)' end
                      from jsonb_array_elements(v_equipe) x), null) else '' end
               || case p.estimativa_fonte when 'aceita' then ' (você aceitou a minha estimativa)' else ' (você disse)' end,
      'sugestao', v_sug);
    v_dias_re := p.dias;
  else
    v_dur := jsonb_build_object(
      'fonte', 'sugerida',
      'dias', v_sug -> 'sugerida', 'dias_otimista', v_sug -> 'dias_otimista', 'dias_realista', v_sug -> 'dias_realista',
      'pessoas', v_sug -> 'pessoas', 'equipe', '[]'::jsonb, 'equipe_dita', false,
      'diarias_otimista', v_sug -> 'diarias_otimista', 'diarias_realista', v_sug -> 'diarias_realista',
      -- Diárias-pessoa da faixa (dias × pessoas) para o backlog: 74 = 3 a 6 (spec §6).
      'dp_otimista', v_sug -> 'diarias_otimista', 'dp_realista', v_sug -> 'diarias_realista',
      'sem_base', coalesce((v_sug ->> 'sem_base')::boolean, false),
      'texto', v_sug ->> 'texto', 'sugestao', v_sug);
    v_dias_re := (v_sug ->> 'dias_realista')::numeric;
  end if;

  v_pres := public.os_presenca_do_dono(p_so_id);

  -- ── Prazo e razão crítica ──
  v_prazo := coalesce(p.precisa_ate, public.agenda_somar_du(v_aprov, c.prazo_padrao_du));
  v_prazo_fnt := case when p.precisa_ate is not null then 'dono' else 'padrão' end;
  if v_dias_re is not null and v_dias_re > 0 then
    v_razao := round(greatest(public.agenda_du_entre(p_hoje, v_prazo), 0) / v_dias_re, 2);
  end if;

  -- ── Execução: parada = em andamento sem diária ligada nos últimos parada_du úteis e sem janela futura ──
  if so.status = 'in_progress' then
    select max(ws.data) into v_ult_diaria
      from public.work_shifts ws
     where ws.data <= p_hoje and ws.tipo in ('normal', 'diaria') and coalesce(ws.fracao, 1) > 0
       and (ws.service_order_id = p_so_id
            or exists (select 1 from public.work_shift_os x where x.shift_id = ws.id and x.service_order_id = p_so_id));
    v_parada := (v_ult_diaria is null or v_ult_diaria < public.agenda_somar_du(p_hoje, -c.parada_du))
                and coalesce(v_ag_ate >= p_hoje, false) is false;
  end if;
  -- FASE 2: (1) a evidência de que a OS andou é a maior entre a última diária ligada, o último meio-dia do plano
  -- cumprido ou parcial e o check-in; (2) com dia no plano de hoje em diante a OS em andamento nunca é parada.
  v_plano := public._agenda_plano_da_os(p_so_id, p_hoje);
  v_tem_futuro := coalesce((v_plano ->> 'proximo_dia')::date >= p_hoje, false);
  v_ult_evid := public._agenda_ultima_evidencia(p_so_id, p_hoje);
  if so.status = 'in_progress' then
    v_parada := (v_ult_evid is null or v_ult_evid < public.agenda_somar_du(p_hoje, -c.parada_du))
                and coalesce(v_ag_ate >= p_hoje, false) is false
                and not v_tem_futuro;
  end if;
  -- FASE 2: fim

  -- ── Restrições: {tipo, quem, texto, bloqueia, desde, compre_ate, pergunta} ──
  if so.status = 'draft' and so.quote_status = 'approved' and so.merged_into_id is null then
    v_r := v_r || jsonb_build_object('tipo', 'orcamento', 'quem', 'dono', 'bloqueia', true, 'desde', v_aprov,
      'compre_ate', null, 'pergunta', 'converter em OS ou arquivar?',
      'texto', format('%s em %s e nunca virou OS: converter ou arquivar?',
                      case when so.signed_at is not null then 'assinado' else 'aprovado' end, to_char(v_aprov, 'DD/MM')));
  end if;
  if (so.quote_status = 'awaiting_deposit' and v_pago = 0) or v_pend > 0 then
    v_r := v_r || jsonb_build_object('tipo', 'sinal', 'quem', 'cliente', 'bloqueia', true, 'desde', v_aprov,
      'compre_ate', null, 'pergunta', null,
      'texto', case when v_pend > 0 then 'esperando o sinal de ' || public._brl(v_pend) else 'esperando o sinal' end);
  end if;
  if so.status = 'awaiting_client' then
    v_r := v_r || jsonb_build_object('tipo', 'cliente', 'quem', 'cliente', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', null, 'texto', 'esperando o cliente');
  end if;
  if p.escopo_em_aberto is not null then
    v_r := v_r || jsonb_build_object('tipo', 'escopo', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', p.escopo_em_aberto, 'texto', p.escopo_em_aberto);
  end if;
  if p.dias is null then
    v_r := v_r || jsonb_build_object('tipo', 'duracao', 'quem', 'dono', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', 'quantos dias e com quem?',
      'texto', case when coalesce((v_sug ->> 'sem_base')::boolean, false)
                    then 'quantos dias e com quem? (o orçamento não dá base para estimar)'
                    else format('quantos dias e com quem? (chute: %s, %s)',
                                public._agenda_faixa_dias((v_sug ->> 'dias_otimista')::numeric, (v_sug ->> 'dias_realista')::numeric),
                                case when (v_sug ->> 'pessoas')::int = 1 then '1 pessoa'
                                     else (v_sug ->> 'pessoas') || ' pessoas' end) end);
  end if;
  -- Com peça embutida em aberto, a pergunta dela já é o "tem peça a comprar?" (mais precisa): não repete.
  if v_n_itens = 0 and not v_conferido and jsonb_array_length(v_embut) = 0 then
    v_r := v_r || jsonb_build_object('tipo', 'material_nao_conferido', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', 'tem peça a comprar?', 'texto', 'tem peça a comprar? (o orçamento não tem nenhuma)');
  end if;
  v_n := jsonb_array_length(v_embut);
  if v_n > 0 then
    v_txt := array_to_string(array(select format('"%s"', e ->> 'curto')
                                     from jsonb_array_elements(v_embut) with ordinality t(e, o) where o <= 2 order by o), ' ou ')
             || case when v_n > 2 then format(' (e mais %s)', v_n - 2) else '' end;
    v_r := v_r || jsonb_build_object('tipo', 'peca_embutida', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', format('tem peça embutida em %s?', v_txt),
      'texto', format('tem peça embutida em %s?', v_txt));
  end if;

  -- O que falta comprar: sem fornecedor/classe (E) pergunta "de quem e quando?"; com classe e sem compra combinada,
  -- "compre até" (programação para trás; se já passou, "comprando hoje, chega por volta de …"). A compra que o dono já
  -- combinou (dia que ainda não passou) sem prazo conhecido NÃO volta a perguntar "de quem e quando": vai à parte.
  select count(*) filter (where e ->> 'situacao' = 'falta'
                          and (((e ->> 'sem_data')::boolean and coalesce((e ->> 'compra_prevista_em')::date < p_hoje, true))
                               or e ->> 'compre_ate' is not null)),
         count(*) filter (where e ->> 'situacao' = 'falta' and (e ->> 'sem_data')::boolean
                          and coalesce((e ->> 'compra_prevista_em')::date < p_hoje, true))
    into v_n_falta, v_n_sem
    from jsonb_array_elements(v_crit) e;
  if v_n_falta > 0 then
    select e into v_compra from jsonb_array_elements(v_crit) with ordinality t(e, o)
     where e ->> 'situacao' = 'falta' and e ->> 'compre_ate' is not null
     order by (e ->> 'compre_ate')::date, o limit 1;
    v_cond := case when v_compra is null then ''
                   when (v_compra ->> 'compre_ate')::date < p_hoje then
                     format('comprando hoje, "%s" chega por volta de %s', v_compra ->> 'curto',
                            public._dia_curto(public.agenda_somar_du(p_hoje, (v_compra ->> 'prazo_du')::int)))
                   else format('"%s": compre até %s', v_compra ->> 'curto',
                               public._dia_curto((v_compra ->> 'compre_ate')::date)) end;
    if v_n_sem > 0 then
      v_txt := case when so.status = 'awaiting_parts' then public._agenda_itens(v_n_falta) || ' sem compra registrada'
                    else public._agenda_itens(v_n_falta) || ' a comprar: de quem e quando?' end;
      v_r := v_r || jsonb_build_object('tipo', 'sem_previsao', 'quem', 'dono', 'bloqueia', true, 'desde', null,
        'compre_ate', v_compra ->> 'compre_ate',
        'pergunta', case when so.status = 'awaiting_parts' then 'o que já está na mão e o que falta? Quando chega?'
                         else format('o material (%s) — compra quando e onde?', public._agenda_itens(v_n_falta)) end,
        'texto', v_txt || case when v_cond <> '' then ' (' || v_cond || ')' else '' end);
    else
      v_r := v_r || jsonb_build_object('tipo', 'compre_ate', 'quem', 'dono', 'bloqueia', true, 'desde', null,
        'compre_ate', v_compra ->> 'compre_ate', 'pergunta', 'compra quando?',
        'texto', public._agenda_itens(v_n_falta) || ' a comprar: ' || v_cond);
    end if;
  end if;

  -- Compra combinada ("compro terça na Casa do Eletricista") sem prazo de entrega conhecido: o que o dono já disse fica
  -- dito; a pergunta é só o que falta — quando chega (com fornecedor) ou de quem (sem).
  select count(*) as n, min((e ->> 'compra_prevista_em')::date) as de, max((e ->> 'compra_prevista_em')::date) as ate,
         bool_and(e ->> 'fornecedor' is not null) as com_forn, count(distinct e ->> 'fornecedor') as n_forn,
         min(e ->> 'fornecedor') as forn, min(e ->> 'curto') as curto
    into v_cc
    from jsonb_array_elements(v_crit) e
   where e ->> 'situacao' = 'falta' and (e ->> 'sem_data')::boolean and (e ->> 'compra_prevista_em')::date >= p_hoje;
  if v_cc.n > 0 then
    v_txt := case when v_cc.de = v_cc.ate then public._dia_curto(v_cc.de)
                  else format('de %s a %s', public._dia_curto(v_cc.de), public._dia_curto(v_cc.ate)) end;
    v_r := v_r || jsonb_build_object('tipo', 'compra_sem_prazo', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null,
      'pergunta', case when v_cc.com_forn then format('quando chega a compra de %s?', v_txt)
                       else format('de quem é a compra de %s?', v_txt) end,
      'texto', case when v_cc.n = 1 then format('"%s"', v_cc.curto) else public._agenda_itens(v_cc.n::int) end
               || ': você compra ' || v_txt
               || case when v_cc.com_forn and v_cc.n_forn = 1 then ', fornecedor ' || v_cc.forn else '' end
               || case when v_cc.com_forn then '; sem prazo de entrega conhecido: quando chega?'
                       else '; de quem? (sem o fornecedor não sei quando chega)' end);
  end if;

  -- Comprado sem previsão e sem classe: "chegou?"; previsão vencida: "venceu em dd/mm: chegou?".
  for v_x in select e from jsonb_array_elements(v_crit) with ordinality t(e, o)
              where e ->> 'situacao' in ('comprado', 'a_caminho')
                and ((e ->> 'sem_data')::boolean or (e ->> 'atrasado')::boolean)
              order by o
  loop
    if (v_x ->> 'atrasado')::boolean then
      v_r := v_r || jsonb_build_object('tipo', 'atrasado', 'quem', 'dono', 'bloqueia', true, 'desde', v_x ->> 'data',
        'compre_ate', null, 'pergunta', format('"%s" chegou?', v_x ->> 'curto'),
        'texto', format('a previsão de "%s" venceu em %s: chegou?', v_x ->> 'curto', to_char((v_x ->> 'data')::date, 'DD/MM')));
    else
      v_r := v_r || jsonb_build_object('tipo', 'comprado_sem_previsao', 'quem', 'dono', 'bloqueia', true,
        'desde', v_x ->> 'comprado_em', 'compre_ate', null,
        'pergunta', format('"%s" chegou?', v_x ->> 'curto'),
        'texto', format('"%s" (%s) chegou?', v_x ->> 'curto',
                        coalesce('pedido em ' || to_char((v_x ->> 'comprado_em')::date, 'DD/MM'), 'comprado, sem previsão')));
    end if;
  end loop;

  if v_d_bem is null or v_d_bem > p_hoje + 1 then
    v_r := v_r || jsonb_build_object('tipo', 'bem', 'quem', 'cliente', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null,
      'texto', case when v_d_bem is null then v_bem_nome || ' está fora, sem data para voltar'
                    else v_bem_nome || ' só fica livre ' || public._dia_curto(v_d_bem) end);
  end if;
  if p.nao_antes_de is not null and p.nao_antes_de > p_hoje then
    v_r := v_r || jsonb_build_object('tipo', 'nao_antes', 'quem', 'terceiro', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null,
      'texto', format('não antes de %s: %s', public._dia_curto(p.nao_antes_de), p.nao_antes_motivo));
  end if;
  if v_parada then
    v_r := v_r || jsonb_build_object('tipo', 'parada', 'quem', 'dono', 'bloqueia', true, 'desde', v_ult_diaria,
      'compre_ate', null, 'pergunta', 'parou?',
      'texto', case when v_ult_diaria is null then 'em andamento e sem diária lançada: parou?'
                    else format('em andamento sem diária desde %s: parou?', to_char(v_ult_diaria, 'DD/MM')) end);
  end if;

  -- Orçamento aprovado que nunca virou OS, ou sinal pendente: quem destrava é a conversão (o dono) ou o sinal (o
  -- cliente), não a compra — comprar peça de um orçamento que pode ser arquivado não é o próximo passo. As perguntas do
  -- material continuam na lista (a visão da OS e a rodada mostram), sem travar até a conversão e o sinal.
  if exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'sinal')) then
    select coalesce(jsonb_agg(case when e ->> 'tipo' in ('atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao',
                                                         'compre_ate', 'peca_embutida', 'material_nao_conferido')
                                   then jsonb_set(e, '{bloqueia}', 'false'::jsonb) else e end order by o), '[]'::jsonb)
      into v_r
      from jsonb_array_elements(v_r) with ordinality t(e, o);
  end if;

  -- A mais forte primeiro: o que trava antes do que só informa, e na ordem do bloco "travado" (spec §5.4).
  select coalesce(jsonb_agg(e order by (e ->> 'bloqueia')::boolean desc,
           array_position(array['parada', 'atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao', 'compre_ate',
                                'peca_embutida', 'material_nao_conferido', 'orcamento', 'escopo', 'sinal', 'cliente',
                                'duracao', 'bem', 'nao_antes'], e ->> 'tipo'), o), '[]'::jsonb)
    into v_r
    from jsonb_array_elements(v_r) with ordinality t(e, o);

  -- ── Estado (o 1º que valer) ──
  v_estado := case
    when p.congelada_ate is not null and p.congelada_ate >= p_hoje then 'congelada'
    when so.status in ('completed', 'invoiced') then 'concluida'
    when so.status = 'cancelled' or so.merged_into_id is not null
         or (so.status = 'draft' and coalesce(so.quote_status, 'draft') not in ('approved', 'awaiting_deposit')) then 'fora_da_carteira'
    when so.status = 'in_progress' then case when v_parada then 'parada' else 'em_execucao' end
    when coalesce(v_ag_ate, v_ag_de) >= p_hoje then 'marcada'
    when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal') then 'sem_sinal'
    when so.status = 'awaiting_client' or v_bem_tudo or p.nao_antes_de > v_horizonte then 'aguardando_cliente'
    when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'escopo')) then 'esperando_voce'
    when v_mat_estado in ('nao_conferido', 'sem_previsao', 'atrasado') then 'aguardando_material'
    else 'pronta' end;
  -- FASE 2: (3) os estados do plano: fixada e programada vêm depois de em execução/parada e antes de marcada; com a
  -- agenda automática ligada a janela antiga é o espelho do plano, e "marcada" não vale (o estado vem das alocações).
  if v_estado not in ('congelada', 'concluida', 'fora_da_carteira', 'em_execucao', 'parada') then
    if coalesce((v_plano ->> 'fixada')::boolean, false) then
      v_estado := 'fixada';
    elsif v_tem_futuro then
      v_estado := 'programada';
    elsif v_estado = 'marcada' and c.modo_proposta = 'ligado' then
      v_estado := case
        when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal') then 'sem_sinal'
        when so.status = 'awaiting_client' or v_bem_tudo or p.nao_antes_de > v_horizonte then 'aguardando_cliente'
        when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'escopo')) then 'esperando_voce'
        when v_mat_estado in ('nao_conferido', 'sem_previsao', 'atrasado') then 'aguardando_material'
        else 'pronta' end;
    end if;
  end if;
  -- FASE 2: fim

  if v_estado in ('concluida', 'fora_da_carteira') and (so.status in ('completed', 'invoiced', 'cancelled')
                                                         or so.merged_into_id is not null) then
    v_r := '[]'::jsonb;
  end if;

  -- A restrição do dono que mais pesa (a 1ª da lista que trava e é dele).
  select e into v_principal from jsonb_array_elements(v_r) with ordinality t(e, o)
   where (e ->> 'bloqueia')::boolean and e ->> 'quem' = 'dono' order by o limit 1;

  v_quase := v_estado = 'aguardando_material'
         and (select count(*) from jsonb_array_elements(v_r) e where (e ->> 'bloqueia')::boolean) = 1
         and v_principal ->> 'tipo' = 'material_nao_conferido';

  -- O texto do estado, para vir depois do nome do cliente ("Lenine: falta você dizer se tem peça a comprar").
  v_estado_txt := case v_estado
    -- "(rever …)" só quando o dia de rever não é o mesmo do fim da espera (é o padrão do rascunho).
    when 'congelada' then 'em espera até ' || public._dia_curto(p.congelada_ate)
                          || case when p.revisar_em is distinct from p.congelada_ate
                                  then coalesce(' (rever ' || public._dia_curto(p.revisar_em) || ')', '') else '' end
    when 'concluida' then case so.status when 'invoiced' then 'faturado' else 'concluído' end
    when 'fora_da_carteira' then public._agenda_rotulo_os(so.status, so.quote_status, so.signed_at is not null, so.juntado_em, false)
    when 'em_execucao' then 'em andamento'
    when 'parada' then case when v_ult_diaria is null then 'em andamento e sem diária lançada'
                            else 'em andamento sem diária desde ' || to_char(v_ult_diaria, 'DD/MM') end
    when 'marcada' then case when v_ag_de is null or v_ag_de = v_ag_ate then 'marcado para ' || public._dia_curto(coalesce(v_ag_ate, v_ag_de))
                             else format('marcado de %s a %s', public._dia_curto(v_ag_de), public._dia_curto(v_ag_ate)) end
    when 'sem_sinal' then (select e ->> 'texto' from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal' limit 1)
    when 'aguardando_cliente' then case
      when so.status = 'awaiting_client' then 'esperando o cliente'
      when v_bem_tudo then case when v_d_bem is null then v_bem_nome || ' está fora, sem data para voltar'
                                else v_bem_nome || ' só fica livre ' || public._dia_curto(v_d_bem) end
      else format('não antes de %s: %s', public._dia_curto(p.nao_antes_de), p.nao_antes_motivo) end
    -- O orçamento parado vem antes do escopo em aberto (a ordem do bloco "travado").
    when 'esperando_voce' then case
      when so.status = 'draft' and so.quote_status = 'approved'
        then format('%s em %s e nunca virou OS', case when so.signed_at is not null then 'assinado' else 'aprovado' end,
                    to_char(v_aprov, 'DD/MM'))
      else 'falta você decidir: ' || p.escopo_em_aberto end
    when 'aguardando_material' then case v_principal ->> 'tipo'
      when 'atrasado' then 'falta você dizer se ' || replace(v_principal ->> 'pergunta', ' chegou?', '') || ' chegou (a previsão venceu)'
      when 'sem_previsao' then case when so.status = 'awaiting_parts'
                                    then format('falta você dizer o que já está na mão e o que falta (%s sem compra registrada)',
                                                public._agenda_itens(v_n_falta))
                                    else 'falta você dizer de quem e quando comprar ' || public._agenda_itens(v_n_falta) end
      when 'comprado_sem_previsao' then 'falta você dizer se ' || replace(v_principal ->> 'texto', ' chegou?', '') || ' chegou'
      when 'compra_sem_prazo' then 'falta você dizer ' || rtrim(v_principal ->> 'pergunta', '?')
      when 'peca_embutida' then 'falta você dizer se tem peça embutida em '
                                || array_to_string(array(select format('"%s"', e ->> 'curto')
                                     from jsonb_array_elements(v_embut) with ordinality t(e, o) where o <= 2 order by o), ' e ')
                                || case when jsonb_array_length(v_embut) > 2
                                        then format(' (e mais %s)', jsonb_array_length(v_embut) - 2) else '' end
      else 'falta você dizer se tem peça a comprar' end
    else -- pronta
      case when v_est is not null and v_est > public.agenda_somar_du(p_hoje, 1) then
             'pronto a partir de ' || public._dia_curto(v_est)
             || case when v_inicio_mat is not null and v_inicio_mat >= v_est_sm then
                  (select case
                        when e ->> 'nivel' in ('B', 'C') then format(', se "%s" chegar %s', e ->> 'curto', public._dia_curto(v_dpm))
                        when e ->> 'situacao' = 'falta' and e ->> 'compra_prevista_em' is not null
                             and (e ->> 'compra_prevista_em')::date >= p_hoje
                          then ', se a compra sair ' || public._dia_curto((e ->> 'compra_prevista_em')::date)
                        when e ->> 'situacao' = 'falta' then ', se comprar hoje'
                        else format(', se "%s" chegar por volta de %s', e ->> 'curto', public._dia_curto(v_dpm)) end
                        from jsonb_array_elements(v_crit) with ordinality t(e, o)
                       where e ->> 'nivel' <> 'A' and (e ->> 'data')::date = v_dpm order by o limit 1)
                else '' end
           else 'pronto para começar' end
  end;
  -- FASE 2: o texto dos estados do plano ("marcado de ter 03/11 a qui 05/11", "(fixado)" quando é fixo).
  if v_estado in ('fixada', 'programada') then
    v_estado_txt := case when (v_plano ->> 'proximo_dia') = (v_plano ->> 'ultimo_dia')
                         then 'marcado para ' || public._dia_curto((v_plano ->> 'proximo_dia')::date)
                         else format('marcado de %s a %s', public._dia_curto((v_plano ->> 'proximo_dia')::date),
                                     public._dia_curto((v_plano ->> 'ultimo_dia')::date)) end
                    || case when v_estado = 'fixada' then ' (fixado)' else '' end;
  end if;
  -- FASE 2: fim

  -- FASE 2: (4) a saída ganha o plano (null sem alocação) e a última evidência; ultima_diaria continua.
  return jsonb_build_object('plano', v_plano, 'ultima_evidencia', v_ult_evid) || jsonb_build_object(
  -- FASE 2: fim
    'ok', true, 'os', so.id, 'numero', so.service_order_number, 'cliente', so.cliente_nome,
    'cliente_curto', public._agenda_nome_curto(so.cliente_nome), 'unidade', so.bem,
    'eh_orcamento', so.status = 'draft', 'status', so.status, 'quote_status', so.quote_status,
    'na_carteira', v_na_cart, 'aprovada_em', v_aprov,
    'estado', v_estado, 'estado_texto', v_estado_txt, 'quase_pronta', v_quase,
    'restricoes', v_r,
    'material', jsonb_build_object(
      'estado', v_mat_estado, 'itens', v_itens, 'dpm', v_dpm,
      'gargalo', (select e ->> 'descricao' from jsonb_array_elements(v_crit) with ordinality t(e, o)
                   where e ->> 'nivel' <> 'A' and v_dpm is not null and (e ->> 'data')::date = v_dpm order by o limit 1),
      'confianca', v_confianca, 'inicio_mat', v_inicio_mat, 'embutidas', v_embut,
      'conferido_em', p.material_conferido_em),
    'duracao', v_dur,
    'presenca_dono', v_pres,
    'est', v_est, 'est_texto', public._dia_curto(v_est), 'est_sem_material', v_est_sm,
    'prazo_efetivo', v_prazo, 'prazo_texto', public._dia_curto(v_prazo), 'prazo_fonte', v_prazo_fnt,
    'razao_critica', v_razao,
    'marcada', case when v_ag_de is not null or v_ag_ate is not null
                    then jsonb_build_object('de', v_ag_de, 'ate', v_ag_ate) end,
    'ultima_diaria', v_ult_diaria);
end;
$function$;

comment on function public.os_prontidao(uuid, date) is
  'Agenda de Produção (Fase 1, P3; Fase 2, P2): a prontidão de uma OS em p_hoje. Estado (o 1º que valer): congelada → concluida → fora_da_carteira → em_execucao/parada → fixada/programada (Fase 2: tem meio-dia vigente de hoje em diante, fixado ou publicado) → marcada (a janela antiga; só fora de modo_proposta ligado) → sem_sinal → aguardando_cliente → esperando_voce → aguardando_material → pronta. Parada (Fase 2) = em andamento, sem evidência (diária ligada, meio-dia cumprido/parcial ou check-in) há parada_du dias úteis e sem dia no plano. Restrições {tipo, quem (dono|cliente|terceiro), texto, bloqueia, desde, compre_ate, pergunta}, a mais forte primeiro. Material efetivo = conta bruta + fato informado em os_material, níveis A (na mão, quantidade completa) / B (previsão do fornecedor, nota, OC, Pix) / C (previsão do dono) / D (sem previsão: comprado em + prazo da classe, ou "se comprar hoje") / E (sem fornecedor nem classe); "material não conferido" com zero itens ou peça embutida em aberto; dpm, início pelo material (chegada + folga_material_du, sem folga remota), est, compre até para trás, prazo efetivo (precisa_ate ou aprovação + prazo_padrao_du) e razão crítica. Saída também com plano (_agenda_plano_da_os; null sem alocação), ultima_evidencia e ultima_diaria. Também aceita OS fora da carteira.';

-- ── 2. Insumos do motor ────────────────────────────────────────────────────────────────────────────────

-- O molde dos meios-dias do que o dono disse, e quanto ainda falta.
create or replace function public.agenda_meios_da_os(p_so_id uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  p          public.os_planejamento%rowtype;
  v_dono     uuid := public._agenda_dono(null);
  v_status   text;
  v_pres     jsonb;
  v_sug      jsonb;
  v_fonte    text;
  v_dias     numeric;
  v_total    int;
  v_plano    jsonb;
  v_cump     numeric := 0;
  v_vig      int := 0;
  v_rest     numeric;
  v_dita     boolean;
  v_dono_t   text;
  v_presenca text;
  v_motivo   text;
  v_dt_m     boolean;
  v_dt_t     boolean;
  v_pm       jsonb;
  v_pt       jsonb;
  v_dm       int;
  v_dtd      int;
  v_pessoas  int;
  v_abre     boolean;
  v_fecha    boolean;
  v_molde    jsonb := '[]'::jsonb;
  v_papel    text[];
  v_t        text;
  k          int;
begin
  select so.status into v_status from public.service_orders so where so.id = p_so_id;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  select * into p from public.os_planejamento where service_order_id = p_so_id;
  v_pres := public.os_presenca_do_dono(p_so_id);
  v_sug := public.os_duracao_sugerida(p_so_id);

  -- Os dias: o que o dono disse (ou aceitou); sem isso, o realista da sugestão (só para reserva e simulação).
  if p.dias is not null then
    v_fonte := p.estimativa_fonte;
    v_dias := p.dias;
  else
    v_fonte := 'sugerida';
    v_dias := case when coalesce((v_sug ->> 'sem_base')::boolean, false) then null
                   else (v_sug ->> 'dias_realista')::numeric end;
  end if;

  -- A equipe dita: o dono (se está nela) e os diaristas por turno ("dia" vale nos dois).
  v_dita := exists (select 1 from public.os_planejamento_equipe e where e.service_order_id = p_so_id);
  select e.turnos into v_dono_t
    from public.os_planejamento_equipe e join public.payees py on py.id = e.payee_id
   where e.service_order_id = p_so_id and (e.payee_id = v_dono or py.kind = 'socio')
   order by e.payee_id is not distinct from v_dono desc, e.payee_id
   limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'nome', public._agenda_nome_curto(py.name))
                            order by e.turnos = 'dia' desc, py.name, e.payee_id)
                    filter (where e.turnos in ('dia', 'manha')), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'nome', public._agenda_nome_curto(py.name))
                            order by e.turnos = 'dia' desc, py.name, e.payee_id)
                    filter (where e.turnos in ('dia', 'tarde')), '[]'::jsonb)
    into v_pm, v_pt
    from public.os_planejamento_equipe e join public.payees py on py.id = e.payee_id
   where e.service_order_id = p_so_id and e.payee_id is distinct from v_dono and py.kind <> 'socio';

  -- A presença do dono: o que ele disse → ele na equipe dita (o turno inteiro nos turnos dele) → a regra d05.
  if v_pres ->> 'fonte' = 'dono' then
    v_presenca := v_pres ->> 'presenca';
    v_motivo := 'você disse';
  elsif v_dono_t is not null then
    v_presenca := 'equipe';
    v_motivo := 'você está na equipe';
  else
    v_presenca := coalesce(v_pres ->> 'presenca', 'abre_e_fecha');
    v_motivo := v_pres ->> 'motivo';
  end if;
  v_dt_m := v_presenca = 'sempre' or (v_presenca = 'equipe' and v_dono_t in ('dia', 'manha'));
  v_dt_t := v_presenca = 'sempre' or (v_presenca = 'equipe' and v_dono_t in ('dia', 'tarde'));

  -- Quantos diaristas por turno: os ditos; sem equipe dita, as pessoas da sugestão (o dono, quando fica o turno
  -- inteiro, é uma delas).
  v_pessoas := coalesce((v_sug ->> 'pessoas')::int, 1);
  if v_dita then
    v_dm := jsonb_array_length(v_pm);
    v_dtd := jsonb_array_length(v_pt);
  else
    v_dm := greatest(v_pessoas - case when v_dt_m then 1 else 0 end, 0);
    v_dtd := greatest(v_pessoas - case when v_dt_t then 1 else 0 end, 0);
  end if;

  -- O que já foi feito e o que já está marcado (d20).
  v_plano := public._agenda_plano_da_os(p_so_id, p_hoje);
  v_cump := coalesce((v_plano ->> 'meios_cumpridos')::numeric, 0);
  v_vig := coalesce((v_plano ->> 'meios_vigentes')::int, 0);
  v_total := case when v_dias is null then null else (v_dias * 2)::int end;
  v_rest := case when v_total is null then null else greatest(v_total - v_cump - v_vig, 0) end;
  v_fecha := v_presenca = 'abre_e_fecha';
  v_abre := v_fecha and coalesce((v_plano ->> 'dias')::int, 0) = 0 and v_cump = 0 and v_status <> 'in_progress';

  -- O molde, como o dono disse e começando de manhã (o motor aplica o turno de verdade de cada meio-dia).
  for k in 1 .. coalesce(v_total, 0) loop
    v_t := case when k % 2 = 1 then 'manha' else 'tarde' end;
    v_papel := '{}';
    if (v_t = 'manha' and v_dt_m) or (v_t = 'tarde' and v_dt_t) then
      v_papel := array['turno'];
    else
      if k = 1 and v_fecha then v_papel := v_papel || 'abertura'::text; end if;
      if k = v_total and v_fecha then v_papel := v_papel || 'fechamento'::text; end if;
    end if;
    v_molde := v_molde || jsonb_build_object('k', k, 'turno', v_t,
      'pessoas_ditas', case when v_t = 'manha' then v_pm else v_pt end,
      'desejado', case when v_t = 'manha' then v_dm else v_dtd end,
      'dono', to_jsonb(v_papel));
  end loop;

  return jsonb_build_object(
    'ok', true, 'os', p_so_id, 'fonte', v_fonte, 'dias', trim_scale(v_dias), 'sem_base', v_dias is null,
    'total', v_total, 'cumpridos', trim_scale(v_cump), 'vigentes', v_vig, 'restantes', trim_scale(v_rest),
    'passos', case when v_rest is null then 0 else ceil(v_rest)::int end,
    'presenca', v_presenca, 'presenca_motivo', v_motivo, 'abre', v_abre, 'fecha', v_fecha,
    -- o motivo da regra d05 (o tipo do meio-dia: diagnóstico, comissionamento), mesmo quando o dono disse a presença
    'regra_motivo', case when v_pres ->> 'fonte' = 'regra' then v_pres ->> 'motivo'
                         else (select case so.service_type when 'diagnosis' then 'diagnóstico' when 'commissioning' then 'comissionamento' end
                                 from public.service_orders so where so.id = p_so_id) end,
    'dono_turno', jsonb_build_object('manha', v_dt_m, 'tarde', v_dt_t),
    'equipe_dita', v_dita, 'pessoas_sugeridas', case when v_dita then null else v_pessoas end,
    'por_turno', jsonb_build_object('manha', jsonb_build_object('pessoas', v_pm, 'desejado', v_dm),
                                    'tarde', jsonb_build_object('pessoas', v_pt, 'desejado', v_dtd)),
    'molde', v_molde);
end;
$function$;

comment on function public.agenda_meios_da_os(uuid, date) is
  'Agenda de Produção (Fase 2, P2): o molde dos meios-dias do que o dono disse — total = dias × 2 (meio dia = 1); por turno os diaristas ditos ("dia" vale nos dois) e quantos (desejado; sem equipe dita, as pessoas da sugestão, e o dono que fica o turno inteiro é uma delas); a presença do dono: o que ele disse → ele na equipe dita (turno nos turnos dele) → a regra d05 (sempre = turno em todos; abre_e_fecha = abertura no 1º e fechamento no último); restantes = total − cumpridos (cumprido/sem registro/passado sem resultado = 1, parcial = 0,5) − os meios-dias vigentes de hoje em diante. Sem os dias ditos: fonte sugerida (dias_realista), só para reserva e simulação. {ok, fonte, dias, total, restantes, passos, presenca, abre, fecha, dono_turno, por_turno, molde[{k, turno, pessoas_ditas, desejado, dono}]}.';

-- A capacidade menos o plano vigente: por pessoa × dia × turno.
create or replace function public.agenda_grade(p_de date, p_ate date, p_hoje date, p_ignorar uuid[] default '{}'::uuid[])
 returns table (payee_id uuid, nome text, eh_dono boolean, dia date, turno text, semana date, situacao text,
                meios_esperados numeric, livre boolean, curta_livre text[], ocupado_por uuid)
 language sql
 stable
 set search_path to 'public'
as $function$
  with
  cap as (select * from public.agenda_capacidade(p_de, p_ate, p_hoje)),
  dono as (select py.id, py.app_user_id from public.payees py where py.id = public._agenda_dono(null)),
  vig as (
    select a.payee_id, a.dia, a.turno, a.presenca, a.periodo, a.service_order_id
      from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.dia between p_de and p_ate
       and not (a.id = any (coalesce(p_ignorar, '{}'::uuid[])))
  ),
  -- O compromisso com hora do dono (agenda_tasks, appointment do login dele) ocupa a ponta que ele cobre.
  compromisso as (
    select tstzrange(t.scheduled_start_at, coalesce(t.scheduled_end_at, t.scheduled_start_at), '[]') as faixa
      from public.agenda_tasks t
      join dono d on d.app_user_id is not null and t.assignee_user_id = d.app_user_id
     where t.kind = 'appointment' and t.status not in ('cancelled', 'done') and t.scheduled_start_at is not null
       and t.scheduled_start_at < ((p_ate + 1)::timestamp at time zone 'America/Sao_Paulo')
       and coalesce(t.scheduled_end_at, t.scheduled_start_at) >= (p_de::timestamp at time zone 'America/Sao_Paulo')
  )
  select k.payee_id, k.pessoa, k.eh_dono, k.dia, k.turno, k.dia - (extract(isodow from k.dia)::int - 1),
         k.situacao, k.meios_esperados,
         k.situacao = 'livre' and oc.os is null,
         -- As pontas do dono (abrir/fechar): em dia útil, também sem padrão (d11); nunca indisponível, feriado ou fim
         -- de semana; livres de plano vigente e de compromisso com hora.
         case when k.eh_dono and k.situacao not in ('indisponivel', 'feriado', 'fim_de_semana') and public.agenda_dia_util(k.dia)
              then array_remove(array[
                     case when not exists (select 1 from vig v where v.payee_id = k.payee_id and v.periodo && pa.ab)
                           and not exists (select 1 from compromisso m where m.faixa && pa.ab) then 'abertura' end,
                     case when not exists (select 1 from vig v where v.payee_id = k.payee_id and v.periodo && pa.fe)
                           and not exists (select 1 from compromisso m where m.faixa && pa.fe) then 'fechamento' end], null)
              else '{}'::text[] end,
         oc.os
    from cap k
    left join lateral (select public.agenda_periodo(k.dia, k.turno, 'abertura') as ab,
                              public.agenda_periodo(k.dia, k.turno, 'fechamento') as fe
                        where k.eh_dono) pa on true
    left join lateral (
      select v.service_order_id as os from vig v
       where v.payee_id = k.payee_id and v.dia = k.dia and v.turno = k.turno
       order by v.presenca = 'turno' desc, v.service_order_id
       limit 1) oc on true
   order by k.eh_dono desc, k.pessoa, k.payee_id, k.dia, k.turno = 'tarde';
$function$;

comment on function public.agenda_grade(date, date, date, uuid[]) is
  'Agenda de Produção (Fase 2, P2): agenda_capacidade menos o plano vigente (publicado/fixado, sem as alocações de p_ignorar, que a proposta vai cancelar). livre = situação livre e nada vigente no turno. curta_livre (só o dono): as pontas abertura/fechamento sem vigente nem compromisso com hora (agenda_tasks appointment do login dele) sobrepondo — vale em dia útil mesmo sem padrão (d11), nunca indisponível, feriado ou fim de semana. ocupado_por = a OS que ocupa o turno (a do turno inteiro primeiro). semana = a segunda-feira ISO.';

-- A classe de uma OS para o motor, pelas restrições da prontidão (não pelo estado).
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
    return jsonb_build_object('classe', 1, 'motivo', case when p_tem_fixada then 'fixada' else 'em_execucao' end,
                              'texto', p_pront ->> 'estado_texto');
  end if;

  -- O que trava antes do material (quem destrava primeiro): orçamento, sinal, cliente, escopo; o bem ou o "não antes de"
  -- além do horizonte; depois o material que trava de vez.
  select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
   where e ->> 'tipo' in ('orcamento', 'sinal', 'cliente', 'escopo') order by o limit 1;
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
  if coalesce((p_meios ->> 'sem_base')::boolean, false) or (p_meios ->> 'total') is null then
    return jsonb_build_object('classe', 4, 'motivo', 'duracao',
                              'texto', 'quantos dias e com quem? (o orçamento não dá base para estimar)');
  end if;

  -- O que só deixa reservar (classe 3), do que mais trava ao que menos.
  if exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' = 'D' and e ->> 'situacao' = 'falta') then
    v_cond := v_cond || 'compra'::text;
  end if;
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
  'Agenda de Produção (Fase 2, P2): a classe da OS para o motor, pelas restrições de os_prontidao e o molde de agenda_meios_da_os — 1 = em execução/parada ou com meio-dia fixado (compromisso, primeiro); 2 = pronta: dias ditos ou aceitos, sem orçamento/sinal/cliente/escopo travando e todo crítico em A, B ou C (compromisso); 3 = o que falta é só compra (D falta, o "compre até"), material comprado sem previsão ou compra combinada sem prazo, conferir o material (zero linhas ou peça embutida) ou dias só sugeridos (só reserva condicionada; condicao_tipo na ordem compra > material > conferir_material > duracao); 4 = nunca: fora da carteira, em espera, material atrasado ou sem previsão, orçamento, sinal, cliente, escopo, o bem ou o "não antes de" além do horizonte, sem base para os dias. {classe, motivo, texto (quem trava), condicao_tipo}.';

-- O aviso de quando o dono marca a OS num dia em que o material ainda não está garantido (o caso da OS-00104: marcada
-- para ter 06/10 com o compressor chegando nesse mesmo dia). A decisão é dele e fica; o aviso vai junto na frase do
-- item, no "Mudei:", na releitura ("Marco mesmo assim?") e na pergunta "chegou?" da véspera (vigia). p_condicao e
-- p_texto são os da classe (_agenda_classe_da_os: condicao_tipo e texto). null = o material dá para o dia.
create or replace function public._agenda_aviso_do_material(p_pront jsonb, p_condicao text, p_texto text, p_dia date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  with m as (select p_pront -> 'material' as mat),
  g as (
    -- o item que chega por último (o da data do material), como na prontidão
    select e from m, jsonb_array_elements(coalesce(m.mat -> 'itens', '[]'::jsonb)) with ordinality t(e, o)
     where coalesce((e ->> 'critico')::boolean, true) and e ->> 'nivel' is distinct from 'A'
       and (e ->> 'data')::date = (m.mat ->> 'dpm')::date
     order by o limit 1)
  select case
    when p_dia is null then null
    when (m.mat ->> 'inicio_mat')::date > p_dia then
      case when (select g.e ->> 'situacao' from g) = 'falta'
           then format('falta comprar %s: comprando hoje, chega por volta de %s (pronto %s)',
                       coalesce('"' || (select g.e ->> 'curto' from g) || '"', 'o material'),
                       public._dia_curto((m.mat ->> 'dpm')::date), public._dia_curto((m.mat ->> 'inicio_mat')::date))
           else format('%s só chega por volta de %s (pronto %s)',
                       coalesce('"' || (select g.e ->> 'curto' from g) || '"', 'o material'),
                       public._dia_curto((m.mat ->> 'dpm')::date), public._dia_curto((m.mat ->> 'inicio_mat')::date)) end
    when p_condicao in ('compra', 'material') and nullif(btrim(coalesce(p_texto, '')), '') is not null then
      'o material ainda não está garantido: ' || rtrim(btrim(p_texto), '.')
  end
  from m;
$function$;

comment on function public._agenda_aviso_do_material(jsonb, text, text, date) is
  'Agenda de Produção (Fase 2, revisão): o aviso do material para um dia que o dono escolheu — "Compressor 12V SS65" só chega por volta de ter 06/10 (pronto qua 07/10)" quando o início pelo material (inicio_mat) é depois do dia; "falta comprar …: comprando hoje, chega por volta de …" quando o item ainda é falta; "o material ainda não está garantido: <o que trava>" na classe 3 de compra ou material. null = o material dá para o dia.';

-- ── 3. Textos curtos do motor ──────────────────────────────────────────────────────────────────────────

-- "ter 03" (sem o mês).
create or replace function public._agenda_dia_sem_mes(p_dia date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select (array['dom','seg','ter','qua','qui','sex','sáb'])[extract(dow from p_dia)::int + 1] || ' ' || to_char(p_dia, 'DD');
$function$;

comment on function public._agenda_dia_sem_mes(date) is 'Agenda de Produção (Fase 2, P2): o dia curto sem o mês ("ter 03").';

-- Uma lista de dias: "ter 03/11", "ter 03 e qua 04/11", "ter 03 a qui 05/11" (3 ou mais dias úteis seguidos),
-- "sex 30/10 e ter 03/11". O feriado de semana entre dois dias seguidos vai dito no fim ("seg 14 a qui 17/06 (ter 15 é
-- aniversário de Itajaí)"), como no título da semana: sem isso "seg 14 a qua 16/06" parece incluir o dia 15.
create or replace function public._agenda_dias_texto(p_dias date[])
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v       date[] := array(select distinct d from unnest(coalesce(p_dias, '{}'::date[])) d where d is not null order by d);
  n       int := cardinality(array(select distinct d from unnest(coalesce(p_dias, '{}'::date[])) d where d is not null));
  v_seg   boolean := true;
  v_itens text[] := '{}';
  v_fer   text[] := '{}';
  v_txt   text;
  i       int;
begin
  if n = 0 then return ''; end if;
  if n = 1 then return public._dia_curto(v[1]); end if;
  for i in 1 .. n - 1 loop
    if public.agenda_du_entre(v[i], v[i + 1]) <> 1 then
      v_seg := false;
    else
      -- dois dias seguidos com feriado de semana entre eles (Finados, 15/06 de Itajaí): o feriado é dito
      v_fer := v_fer || array(select format('%s é %s', public._agenda_dia_sem_mes(g::date), public.agenda_feriado(g::date))
                                from generate_series(v[i] + 1, v[i + 1] - 1, interval '1 day') g
                               where extract(isodow from g)::int <= 5 and public.agenda_feriado(g::date) is not null
                               order by g);
    end if;
  end loop;
  if v_seg and n >= 3 then
    v_txt := format('%s a %s',
                    case when to_char(v[1], 'MM') = to_char(v[n], 'MM') then public._agenda_dia_sem_mes(v[1]) else public._dia_curto(v[1]) end,
                    public._dia_curto(v[n]));
  else
    for i in 1 .. n - 1 loop
      v_itens := v_itens || case when to_char(v[i], 'MM') = to_char(v[n], 'MM') then public._agenda_dia_sem_mes(v[i])
                                 else public._dia_curto(v[i]) end;
    end loop;
    v_txt := public._agenda_lista(v_itens || public._dia_curto(v[n]), null);
  end if;
  return v_txt || coalesce(' (' || nullif(array_to_string(v_fer, ', '), '') || ')', '');
end;
$function$;

comment on function public._agenda_dias_texto(date[]) is
  'Agenda de Produção (Fase 2, P2): os dias em texto curto — "ter 03/11", "ter 03 e qua 04/11", "ter 03 a qui 05/11" (3+ dias úteis seguidos: o feriado no meio não quebra a sequência), "sex 30/10 e ter 03/11". O feriado de seg a sex entre dois dias seguidos vai dito no fim, como no título da semana: "seg 14 a qui 17/06 (ter 15 é aniversário de Itajaí)", "sex 30/10 e ter 03/11 (seg 02 é Finados)".';

-- "ter 03/11 de manhã", "ter 03/11 à tarde".
create or replace function public._agenda_meio_texto(p_dia date, p_turno text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select public._dia_curto(p_dia) || case when p_turno = 'manha' then ' de manhã' else ' à tarde' end;
$function$;

comment on function public._agenda_meio_texto(date, text) is 'Agenda de Produção (Fase 2, P2): o meio-dia em texto ("ter 03/11 de manhã").';

-- A faixa de uma reserva: "qui 05/11 à tarde a ter 10/11 de manhã", "ter 03 a qui 05/11", "sex 06/11".
create or replace function public._agenda_faixa_texto(p_d1 date, p_t1 text, p_d2 date, p_t2 text)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
begin
  if p_d1 = p_d2 then
    return case when p_t1 = p_t2 then public._agenda_meio_texto(p_d1, p_t1) else public._dia_curto(p_d1) end;
  end if;
  if p_t1 = 'manha' and p_t2 = 'tarde' then
    return case when public.agenda_du_entre(p_d1, p_d2) = 1 then public._agenda_dias_texto(array[p_d1, p_d2]::date[])
                else format('%s a %s', case when to_char(p_d1, 'MM') = to_char(p_d2, 'MM') then public._agenda_dia_sem_mes(p_d1)
                                            else public._dia_curto(p_d1) end, public._dia_curto(p_d2)) end;
  end if;
  return format('%s%s a %s', case when to_char(p_d1, 'MM') = to_char(p_d2, 'MM') then public._agenda_dia_sem_mes(p_d1)
                                  else public._dia_curto(p_d1) end,
                case when p_t1 = 'manha' then ' de manhã' else ' à tarde' end,
                public._agenda_meio_texto(p_d2, p_t2));
end;
$function$;

comment on function public._agenda_faixa_texto(date, text, date, text) is
  'Agenda de Produção (Fase 2, P2): do 1º ao último meio-dia — "qui 05 à tarde a ter 10/11 de manhã"; de manhã a tarde vira só os dias.';

-- O nome da OS numa frase: "Lenine (OS-00074)".
create or replace function public._agenda_rotulo_da_os(p_os uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(public._agenda_nome_curto(cl.name) || ' (' || so.service_order_number || ')', so.service_order_number)
    from public.service_orders so left join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
$function$;

comment on function public._agenda_rotulo_da_os(uuid) is 'Agenda de Produção (Fase 2, P2): "Lenine (OS-00074)".';

-- Quem vai num bloco: "você abre e fecha, Roberto os 2 dias, João à tarde". p_alocs = [{payee_id, nome, dia, turno,
-- presenca}]; o dono é "você".
create or replace function public._agenda_pessoas_texto(p_alocs jsonb, p_dono uuid)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_partes text[] := '{}';
  v_meios  int;
  v_dias   int;
  v_manhas int;
  v_tardes int;
  r        record;
begin
  with a as (select * from jsonb_to_recordset(coalesce(p_alocs, '[]'::jsonb))
                    as x(payee_id uuid, nome text, dia date, turno text, presenca text))
  select count(distinct (a.dia, a.turno)), count(distinct a.dia),
         count(distinct (a.dia, a.turno)) filter (where a.turno = 'manha'),
         count(distinct (a.dia, a.turno)) filter (where a.turno = 'tarde')
    into v_meios, v_dias, v_manhas, v_tardes
    from a where a.presenca = 'turno';

  -- Você.
  select count(*) filter (where a.presenca = 'turno') as tur,
         count(*) filter (where a.presenca = 'turno' and a.turno = 'manha') as tur_m,
         count(*) filter (where a.presenca = 'turno' and a.turno = 'tarde') as tur_t,
         bool_or(a.presenca = 'abertura') as ab, bool_or(a.presenca = 'fechamento') as fe,
         array_agg(a.dia) filter (where a.presenca = 'turno') as dias
    into r
    from jsonb_to_recordset(coalesce(p_alocs, '[]'::jsonb)) as a(payee_id uuid, nome text, dia date, turno text, presenca text)
   where a.payee_id = p_dono;
  if r.tur > 0 and r.tur = v_meios then
    v_partes := v_partes || 'você'::text;
  elsif r.tur > 0 and r.tur = r.tur_m and r.tur_m = v_manhas then
    v_partes := v_partes || 'você de manhã'::text;
  elsif r.tur > 0 and r.tur = r.tur_t and r.tur_t = v_tardes then
    v_partes := v_partes || 'você à tarde'::text;
  elsif r.tur > 0 then
    v_partes := v_partes || ('você (' || public._agenda_dias_texto(r.dias) || ')');
  end if;
  if coalesce(r.ab, false) and coalesce(r.fe, false) then
    v_partes := v_partes || 'você abre e fecha'::text;
  elsif coalesce(r.ab, false) then
    v_partes := v_partes || 'você abre'::text;
  elsif coalesce(r.fe, false) then
    v_partes := v_partes || 'você fecha'::text;
  end if;

  -- A equipe, na ordem em que entra.
  for r in
    select a.nome, count(*) as m, count(*) filter (where a.turno = 'manha') as mm, count(*) filter (where a.turno = 'tarde') as mt,
           count(distinct a.dia) as nd, array_agg(a.dia) as dias, min(a.dia) as d1
      from jsonb_to_recordset(coalesce(p_alocs, '[]'::jsonb)) as a(payee_id uuid, nome text, dia date, turno text, presenca text)
     where a.payee_id is distinct from p_dono and a.presenca = 'turno'
     group by a.payee_id, a.nome
     order by min(a.dia), min(case when a.turno = 'manha' then 1 else 2 end), a.nome, a.payee_id
  loop
    v_partes := v_partes || case
      when r.m = v_meios and v_dias = 1 and v_meios = 2 then r.nome || ' o dia todo'
      when r.m = v_meios and v_dias = 1 then r.nome
      when r.m = v_meios then format('%s os %s dias', r.nome, v_dias)
      when r.m = r.mt and r.mt = v_tardes then r.nome || ' à tarde'
      when r.m = r.mm and r.mm = v_manhas then r.nome || ' de manhã'
      else r.nome || ' (' || public._agenda_dias_texto(r.dias) || ')' end;
  end loop;
  return array_to_string(v_partes, ', ');
end;
$function$;

comment on function public._agenda_pessoas_texto(jsonb, uuid) is
  'Agenda de Produção (Fase 2, P2): quem vai num bloco, em texto — "você abre e fecha, Roberto os 2 dias, João à tarde"; "você" para o dono; quem não vai em todos os meios-dias leva os dias.';

-- Os arrays do contexto (jsonb → array do Postgres).
create or replace function public._agenda_ints(p jsonb)
 returns integer[]
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p is null or jsonb_typeof(p) <> 'array' then '{}'::integer[] else translate(p::text, '[]', '{}')::integer[] end;
$function$;

create or replace function public._agenda_bools(p jsonb)
 returns boolean[]
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p is null or jsonb_typeof(p) <> 'array' then '{}'::boolean[] else translate(p::text, '[]', '{}')::boolean[] end;
$function$;

comment on function public._agenda_ints(jsonb) is 'Agenda de Produção (Fase 2, P2): um array jsonb de inteiros como integer[] (o contexto do motor).';
comment on function public._agenda_bools(jsonb) is 'Agenda de Produção (Fase 2, P2): um array jsonb de booleanos como boolean[] (o contexto do motor).';

-- ── 4. O encaixe, em funções pequenas ──────────────────────────────────────────────────────────────────
-- A grade vira arrays (1-based): dia i = d_ini + i − 1; meio-dia h = 2(i − 1) + 1 (manhã) ou + 2 (tarde); célula da
-- pessoa p = (p − 1)·nh + h; semana w = (dia − segunda da 1ª semana) / 7 + 1, (p − 1)·nw + w. ocup e as frentes guardam o
-- índice da OS (em oss), negativo quando é reserva (a OS pode usar a própria reserva ao virar compromisso).

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

  -- O local de cada OS (a marina, senão a cidade do cliente), para o desempate "mesmo local".
  select coalesce(array_agg(q.loc order by q.o), '{}'::int[]) into v_loc
    from (select k.o, case when k.chave is null then 0 else dense_rank() over (order by k.chave)::int end as loc
            from (select u.o, coalesce('m:' || so.marina_id::text, 'c:' || nullif(lower(btrim(cl.city)), '')) as chave
                    from unnest(v_oss) with ordinality u(os, o)
                    left join public.service_orders so on so.id = u.os
                    left join public.clients cl on cl.id = so.client_id) k) q;

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
  'Agenda de Produção (Fase 2, P2): a grade do motor em arrays (agenda_grade de p_d_ini a p_d_fim, sem as alocações de p_ignorar): pessoas (você primeiro), dias úteis, semana ISO de cada dia, quem está livre em cada meio-dia (cap), as pontas livres do dono (curta: 1 abertura, 2 fechamento), o que o vigente ocupa (ocup, frentes: o índice da OS em oss, negativo = reserva), o uso por pessoa e semana (compromisso e reserva) e os tetos floor(carga_max × esperado) e floor(esperado) — o esperado só de dia útil (o sábado combinado não sobe o teto). As OS de p_fila vêm primeiro em oss.';

-- Um início (d0) para uma OS: percorre os meios-dias desde a manhã de d0; o bloco começa no 1º meio-dia de d0 em que o
-- 1º passo sai inteiro (dono e equipe); pula dia não útil e dia em que o bem está fora (não conta interrupção); um dia
-- útil inteiro sem a OS depois de começar = 1 interrupção. null = esse início não dá.
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
begin
  if v_n <= 0 or p_d0 is null or p_d0 < 1 or p_d0 > v_nd then return null; end if;
  if not p_util[p_d0] or p_d0 = any (v_bem) then return null; end if;
  v_loc := coalesce(p_loc[v_i], 0);
  v_h := 2 * (p_d0 - 1) + 1;
  v_dia := p_d0;

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
  'Agenda de Produção (Fase 2, P2): tenta encaixar a OS p_o (i, passos, abre, fecha, dt_m/dt_t = o dono o turno inteiro, dm/dtd = diaristas desejados, pm/pt = os ditos por turno, fixa = a pessoa pedida, bem = dias com o bem fora) começando no dia p_d0. O bloco começa no 1º meio-dia de d0 em que o 1º passo sai inteiro; cada passo pede: no máximo wip_max OS no meio-dia (contando a própria), o dono conforme o molde (turno livre e abaixo do teto, ou a ponta da abertura no 1º), e os diaristas desejados (os ditos, senão trocados por quem estava no meio-dia anterior, a menor carga, o nome) livres, abaixo do teto (p_teto × p_uso) e com lugar na semana inteira (p_rest = 100% − compromisso − reserva); meio-dia sem o desejado = lacuna; dia útil inteiro sem passo depois de começar = interrupção (mais que interrupcoes_max = inválido); dia não útil e bem fora são pulados. O fechamento vai na última ponta ou desliza para a próxima ponta livre. Reserva (p_reserva) = só diaristas, sem o dono. Devolve {d0, ini, fim, int, md (turnos do dono), mesmo (local), p[], h[], pr[] (0 turno, 1 abertura, 2 fechamento)} ou null.';

-- Grava um bloco na grade: a célula, as pontas do dono, as frentes e o uso da semana.
create or replace function public._agenda_ocupar(p_g jsonb, p_sem int[], p_b jsonb, p_i int, p_reserva boolean,
                                                 inout p_ocup int[], inout p_curta int[], inout p_fr int[],
                                                 inout p_uc int[], inout p_ur int[])
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_nh    int := (p_g ->> 'nh')::int;
  v_nw    int := (p_g ->> 'nw')::int;
  v_dono  int := (p_g ->> 'dono')::int;
  v_mark  int := case when p_reserva then -p_i else p_i end;
  v_p     int[] := public._agenda_ints(p_b -> 'p');
  v_h     int[] := public._agenda_ints(p_b -> 'h');
  v_pr    int[] := public._agenda_ints(p_b -> 'pr');
  v_cel   int;
  v_k     int;
  v_w     int;
  v_achou boolean;
  j       int;
  s       int;
begin
  for j in 1 .. coalesce(cardinality(v_p), 0) loop
    v_cel := (v_p[j] - 1) * v_nh + v_h[j];
    v_w := p_sem[(v_h[j] + 1) / 2];
    if v_pr[j] = 0 then
      p_ocup[v_cel] := v_mark;
      if v_p[j] = v_dono then p_curta[v_h[j]] := 0; end if;
      v_k := (v_p[j] - 1) * v_nw + v_w;
      if p_reserva then p_ur[v_k] := p_ur[v_k] + 1; else p_uc[v_k] := p_uc[v_k] + 1; end if;
    else
      p_curta[v_h[j]] := p_curta[v_h[j]] & (case when v_pr[j] = 1 then 2 else 1 end);
      if p_ocup[v_cel] = 0 or p_ocup[v_cel] = -p_i then p_ocup[v_cel] := v_mark; end if;
    end if;
    v_achou := false;
    for s in 1 .. 4 loop
      v_k := (v_h[j] - 1) * 4 + s;
      if abs(p_fr[v_k]) = p_i then
        if p_fr[v_k] < 0 and v_mark > 0 then p_fr[v_k] := v_mark; end if;
        v_achou := true;
        exit;
      end if;
    end loop;
    if not v_achou then
      for s in 1 .. 4 loop
        v_k := (v_h[j] - 1) * 4 + s;
        if p_fr[v_k] = 0 then p_fr[v_k] := v_mark; exit; end if;
      end loop;
    end if;
  end loop;
end;
$function$;

comment on function public._agenda_ocupar(jsonb, integer[], jsonb, integer, boolean, integer[], integer[], integer[], integer[], integer[]) is
  'Agenda de Produção (Fase 2, P2): grava um bloco de _agenda_tentar_bloco na grade do motor — a célula de cada pessoa (o índice da OS; negativo = reserva), as pontas do dono, as frentes do meio-dia e o uso da semana (compromisso ou reserva; a presença curta do dono não conta).';

-- O melhor de dois inícios: termina mais cedo, menos turnos do dono, menos interrupções, o mesmo local, o 1º início.
create or replace function public._agenda_melhor(p_a jsonb, p_b jsonb)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  select row((p_a ->> 'fim')::int, (p_a ->> 'md')::int, (p_a ->> 'int')::int, not (p_a ->> 'mesmo')::boolean, (p_a ->> 'd0')::int)
       < row((p_b ->> 'fim')::int, (p_b ->> 'md')::int, (p_b ->> 'int')::int, not (p_b ->> 'mesmo')::boolean, (p_b ->> 'd0')::int);
$function$;

comment on function public._agenda_melhor(jsonb, jsonb) is
  'Agenda de Produção (Fase 2, P2): o bloco p_a é melhor que p_b por (fim, meios-dias de turno do dono, interrupções, mesmo local primeiro, d0) — termina mais cedo primeiro.';

-- O melhor início entre os dias úteis p_de..p_ate (no máximo p_inicios inícios tentados).
create or replace function public._agenda_melhor_bloco(p_g jsonb, p_util boolean[], p_sem int[], p_cap int[], p_curta int[],
                                                       p_ocup int[], p_fr int[], p_teto int[], p_uso int[], p_rest int[], p_loc int[],
                                                       p_o jsonb, p_de int, p_ate int, p_inicios int, p_reserva boolean)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_nd    int := (p_g ->> 'nd')::int;
  v_bem   int[] := public._agenda_ints(p_o -> 'bem');
  v_min_h int := coalesce((p_o ->> 'min_h')::int, 1);
  v_d0    int := greatest(coalesce(p_de, 1), 1);
  v_n     int := 0;
  b       jsonb;
  v_best  jsonb;
begin
  while v_d0 <= least(coalesce(p_ate, v_nd), v_nd) and v_n < p_inicios loop
    if p_util[v_d0] and not (v_d0 = any (v_bem)) then
      -- quem já termina antes deste início começar não perde para nenhum início daqui em diante
      exit when v_best is not null and (v_best ->> 'fim')::int < 2 * (v_d0 - 1) + 1;
      v_n := v_n + 1;
      b := public._agenda_tentar_bloco(p_g, p_util, p_sem, p_cap, p_curta, p_ocup, p_fr, p_teto, p_uso, p_rest, p_loc,
                                       p_o, v_d0, p_reserva, v_min_h);
      if b is not null and (v_best is null or public._agenda_melhor(b, v_best)) then v_best := b; end if;
    end if;
    v_d0 := v_d0 + 1;
  end loop;
  return v_best;
end;
$function$;

comment on function public._agenda_melhor_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, integer, integer, boolean) is
  'Agenda de Produção (Fase 2, P2): tenta a OS nos primeiros p_inicios dias úteis (sem o bem fora) de p_de a p_ate e devolve o melhor bloco (_agenda_melhor), ou null.';

-- O bloco sem o dono (a reserva por teto guarda o lugar da equipe, nunca a presença do dono).
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
$function$;

comment on function public._agenda_so_diaristas(jsonb, integer) is 'Agenda de Produção (Fase 2, P2): o bloco só com os turnos da equipe (sem o dono); null se não sobra ninguém.';

-- A fila inteira: o compromisso (classes 1 e 2, na ordem), depois as reservas — por teto (a OS da classe 2 que não
-- coube na carga, até 100%), condicionada (classe 3) e no pátio (o bem fora, só a equipe).
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
  'Agenda de Produção (Fase 2, P2): o guloso serial sobre a grade do contexto. 1) compromisso: classes 1 e 2 na ordem (ordem), cada uma no melhor início (_agenda_melhor_bloco) a partir do est (ou dentro de fixar_de..fixar_ate), com o teto de 80% (100% com acima_da_carga ou pedido do dono), gravando na grade; sem encaixe = fora (sem_encaixe, fixar_nao_cabe, padrao_do_dono). 2) reservas até 100%: teto (classe 2 que não coube na janela), condicionada (classe 3, a partir do est_cond) e pátio (patio_passos nos dias com o bem fora). Na semana (semana = true) só conta o que começa entre jan_de e jan_ate (na_janela). Devolve {colocadas[{i, tipo, reserva_de, d0, ini, fim, int, md, mesmo, p, h, pr, na_janela}], fora[{i, motivo}]}.';

-- O contexto com os blocos da janela já gravados (a grade que a decisão vai encontrar).
create or replace function public._agenda_ctx_com(p_ctx jsonb, p_col jsonb)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_g     jsonb := jsonb_build_object('nh', p_ctx -> 'nh', 'nw', p_ctx -> 'nw', 'dono', p_ctx -> 'dono');
  v_sem   int[] := public._agenda_ints(p_ctx -> 'sem');
  v_ocup  int[] := public._agenda_ints(p_ctx -> 'ocup');
  v_curta int[] := public._agenda_ints(p_ctx -> 'curta');
  v_fr    int[] := public._agenda_ints(p_ctx -> 'fr');
  v_uc    int[] := public._agenda_ints(p_ctx -> 'uso_c');
  v_ur    int[] := public._agenda_ints(p_ctx -> 'uso_r');
  b       jsonb;
begin
  for b in select e from jsonb_array_elements(coalesce(p_col, '[]'::jsonb)) e
            where coalesce((e ->> 'na_janela')::boolean, true)
  loop
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, b, (b ->> 'i')::int, b ->> 'tipo' = 'reserva', v_ocup, v_curta, v_fr, v_uc, v_ur) x;
  end loop;
  return p_ctx || jsonb_build_object('ocup', to_jsonb(v_ocup), 'curta', to_jsonb(v_curta), 'fr', to_jsonb(v_fr),
                                     'uso_c', to_jsonb(v_uc), 'uso_r', to_jsonb(v_ur));
end;
$function$;

comment on function public._agenda_ctx_com(jsonb, jsonb) is 'Agenda de Produção (Fase 2, P2): o contexto do motor com os blocos (na janela) gravados.';

-- Por que a OS não cabe no dia pedido: o 1º motivo na manhã do dia (o feriado, o bem, você, quem o dono disse, as
-- frentes).
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
  'Agenda de Produção (Fase 2, P2): o motivo, em palavras, de a OS não caber no dia pedido (a manhã do dia): feriado, fim de semana ("a agenda automática não marca sábado (sábado é só combinando direto com a equipe)"), o bem fora, você ocupado ou fora de campo, quem o dono disse ocupado ("o Roberto já está no Vanderlei"), fora ou com a semana cheia, as frentes cheias; senão "falta gente nesse dia".';

-- ── 5. A regra única do que é crítico ──────────────────────────────────────────────────────────────────
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
begin
  select pl.precisa_ate into v_precisa from public.os_planejamento pl where pl.service_order_id = p_os;
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
  return null;
end;
$function$;

comment on function public._agenda_criticidade(uuid, date, date, date, date, date, uuid[], uuid[]) is
  'Agenda de Produção (Fase 2, P2): a regra única do que é crítico (pergunta antes), na ordem — nao_cabe (precisa_ate dito pelo dono e o fim novo passa dela, sem que o fim de antes já passasse); com o fim publicado andando: atraso_longo (atraso_longo_dias corridos ou mais), segundo_atraso (a OS já teve atraso executado e não desfeito), remarcar_confirmado (o cliente confirmou o 1º dia e o novo início passa de remarcar_confirmado_du dias úteis); fixada_pelo_dono (p_cancela tem meio-dia fixado pelo dono fora de p_violadas). null = o gestor faz sozinho. A mesma regra que agenda_saude reconfere.';

-- ── 6. A validação: 14 regras duras ────────────────────────────────────────────────────────────────────

-- Os itens que o agenda_aplicar aplica: os da lista de OS (todas, sem lista) que não são críticos, e os críticos
-- decididos por p_pergunta.
create or replace function public._agenda_itens_escolhidos(p_itens jsonb, p_os uuid[], p_pergunta uuid)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(i order by k), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) with ordinality t(i, k)
   where (p_os is null or (i ->> 'os')::uuid = any (p_os))
     and (i ->> 'critica' is null or (p_pergunta is not null and (i ->> 'decisao')::uuid = p_pergunta));
$function$;

comment on function public._agenda_itens_escolhidos(jsonb, uuid[], uuid) is
  'Agenda de Produção (Fase 2, P2): os itens de uma proposta que entram ao aplicar — das OS de p_os (todas, sem lista), os não críticos e os críticos decididos pela pergunta p_pergunta.';

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
  'Agenda de Produção (Fase 2, P2): as 14 regras duras sobre os itens (criar e cancelar) de uma proposta, contra o banco de agora — (1) pessoa ativa e livre no turno (a ponta livre na presença curta, sem compromisso com hora), sem feriado; (2) sem choque com o vigente nem dentro da proposta; (3) não antes do dia em que fica pronta; (4) a presença do dono conforme a regra; (5) alguém em cada meio-dia; (6) o teto por pessoa e semana; (7) nada no congelado (salvo evento real e pedido do dono) nem no que começou; (8) o fixado só sai autorizado; (9) a OS na carteira; (10) classe 4 nunca; (11) reserva condicionada não vira compromisso; (12) wip_max por meio-dia; (13) no máximo interrupcoes_max dias parados; (14) com p_aplicar, item crítico só com a pergunta respondida. Lista vazia = ok; cada violação {regra, os, numero, pessoa, dia, turno, texto}.';

create or replace function public.agenda_validar(p_proposta uuid, p_os uuid[] default null, p_hoje date default public._hoje_brt(),
                                                 p_agora timestamptz default now(), p_pergunta uuid default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_p public.agenda_propostas%rowtype;
begin
  select * into v_p from public.agenda_propostas where id = p_proposta;
  if not found then
    raise exception 'Não encontrei esse plano.' using errcode = 'P0002';
  end if;
  return public._agenda_validar_itens(public._agenda_itens_escolhidos(v_p.itens, p_os, p_pergunta), v_p.parametros,
                                      p_hoje, p_agora, true);
end;
$function$;

comment on function public.agenda_validar(uuid, uuid[], date, timestamptz, uuid) is
  'Agenda de Produção (Fase 2, P2): valida o que agenda_aplicar aplicaria de uma proposta (as OS de p_os, ou todas; os não críticos e os críticos decididos por p_pergunta) pelas 14 regras duras de _agenda_validar_itens, contra o banco de agora. Lista vazia = ok.';

-- ── 7. A proposta ──────────────────────────────────────────────────────────────────────────────────────

-- A estabilidade: o que do plano vigente (de hoje em diante, sem resultado) não pode mais acontecer, e por quê. A OS
-- que perdeu um meio-dia perde também o resto daquele meio-dia e o que tinha publicado depois do congelado (o que sobra
-- volta à fila como um bloco só). O fixado pelo dono só sai quando é impossível (a pessoa não vem, a OS saiu).
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
begin
  select max(a.dia) into v_ate
    from public.agenda_alocacoes a
   where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
     and (a.service_order_id = any (p_escopo) or (p_semana and not (a.service_order_id = any (p_cart))));
  if v_ate is null then
    return '[]'::jsonb;
  end if;
  select py.app_user_id into v_login from public.payees py where py.id = public._agenda_dono(null);

  with
  alvo as (
    select a.*, a.dia <= p_cong as congelado
      from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
       and (a.service_order_id = any (p_escopo) or (p_semana and not (a.service_order_id = any (p_cart))))
  ),
  cap as (select * from public.agenda_capacidade(p_hoje, v_ate, p_hoje)),
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
             when coalesce(pl.bem_indisponivel @> a.dia, false) then 'cliente'
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
  tudo as (
    select v.id, v.service_order_id, v.por_que, true as violada, v.congelado, v.tipo, v.estado, v.fixado_por, v.reserva_de,
           v.payee_id, v.dia, v.turno, v.presenca from violadas v
    union
    select m.id, m.service_order_id, 'replanejado', false, m.congelado, m.tipo, m.estado, m.fixado_por, m.reserva_de,
           m.payee_id, m.dia, m.turno, m.presenca from mesmo_meio m
    union
    select d.id, d.service_order_id, 'replanejado', false, d.congelado, d.tipo, d.estado, d.fixado_por, d.reserva_de,
           d.payee_id, d.dia, d.turno, d.presenca from depois d
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
  'Agenda de Produção (Fase 2, P2): a etapa da estabilidade — cada alocação vigente de hoje em diante, sem resultado, das OS do escopo (e, na semana, das que saíram da carteira) que não pode mais acontecer: a OS saiu da carteira, está esperando o cliente ou concluída (os_saiu/cliente); o dia dentro da espera que o dono pôs (espera: só até congelada_ate, o depois fica); a pessoa não está mais livre ou a ponta do dono ficou ocupada por compromisso com hora (pessoa); o bem fora ou o "não antes de" (cliente); o material atrasado, sem previsão ou chegando depois do dia (material); a reserva condicionada vencida sem a condição (condicao_vencida). O fixado pelo dono só pelas três primeiras (a espera é dele também). Junto vão o resto do meio-dia quebrado e os meios-dias publicados da OS depois do congelado (replanejado). [{alocacao_id, os, motivo, violada, congelado, tipo, estado, fixado_por, reserva_de, payee_id, dia, turno, presenca}].';

-- A alocação de um bloco, para o item: [{payee_id, nome, dia, turno, presenca}].
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
$function$;

comment on function public._agenda_alocs_do_bloco(jsonb, jsonb) is 'Agenda de Produção (Fase 2, P2): as alocações de um bloco do motor em ids e datas ({payee_id, nome, dia, turno, presenca}).';

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
  'Agenda de Produção (Fase 2, P2): o motor — guloso serial determinístico (mesma entrada, mesma saída). Escopo semana (publica os blocos que COMEÇAM de segunda a sábado da semana seguinte), os ou replano (as OS de p_os, depois do congelado, no horizonte). Etapas: estabilidade (_agenda_violacoes: só sai o que não pode mais acontecer; o publicado não violado nunca vira "mover"), a fila por classe (_agenda_classe_da_os) na ordem (classe, prioridade do dono, razão crítica, sinal pago, aprovação, número), o encaixe (_agenda_encaixar: congelamento hoje + o próximo dia útil, salvo evento real e pedido do dono; ≤ wip_max frentes; o dono como tambor; teto de carga_max por pessoa e semana; multi-dia com no máximo interrupcoes_max dias parados), a sobrecarga (a OS com data dita que não cabe vira a pergunta crítica nao_cabe, com as opções simuladas e a recomendação; o banco nunca escolhe), o atraso crítico de quem já tinha plano (_agenda_criticidade), as reservas (teto, condicionada com a data-limite, pátio), a validação (_agenda_validar_itens: inválida nunca sai), o diff (itens), as OS de fora com quem trava, a carga, a pontuação e os textos. Restrições: {fixar:[{os, de, ate, pessoa}], tirar:[os], so_depois_de:[{os, dia}], atrasar:[os], aceitar_atraso:[os], acima_da_carga, decisao}. Com p_persistir: agenda_propostas (modo = modo_proposta; a aberta anterior fica obsoleta), as alocações em estado proposta e as perguntas críticas. Sem persistir, o texto termina com "É simulação: não muda nada.". Só service_role.';

-- A condição de uma reserva condicionada e a data-limite, a partir do 1º dia dela: compra → o "compre até" daquele
-- início (a data combinada, se houver); material, conferir o material e os dias → o dia antes do congelamento dele.
create or replace function public._agenda_condicao_da_reserva(p_os uuid, p_tipo text, p_dia date, p_pront jsonb, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_item jsonb;
  v_ate  date;
  v_txt  text;
  v_forn text;
begin
  if p_tipo = 'compra' then
    select e into v_item from jsonb_array_elements(coalesce(p_pront #> '{material,itens}', '[]'::jsonb)) with ordinality t(e, o)
     where coalesce((e ->> 'critico')::boolean, true) and e ->> 'nivel' = 'D' and e ->> 'situacao' = 'falta'
     order by coalesce((e ->> 'prazo_du')::int, 0) desc, o limit 1;
    v_ate := greatest(coalesce((v_item ->> 'compra_prevista_em')::date,
                               public.agenda_somar_du(p_dia, -(cf.folga_material_du + coalesce((v_item ->> 'prazo_du')::int, 0)))),
                      p_hoje);
    v_forn := coalesce(', fornecedor ' || nullif(v_item ->> 'fornecedor', ''), '');
    v_txt := case when v_ate <= p_hoje then format('se "%s" estiver na mão (comprando hoje%s)', v_item ->> 'curto', v_forn)
                  else format('se "%s" estiver na mão (compre até %s%s)', v_item ->> 'curto', public._dia_curto(v_ate), v_forn) end;
  elsif p_tipo = 'material' then
    select e into v_item from jsonb_array_elements(coalesce(p_pront #> '{material,itens}', '[]'::jsonb)) with ordinality t(e, o)
     where coalesce((e ->> 'critico')::boolean, true) and e ->> 'nivel' is distinct from 'A'
     order by (e ->> 'situacao') = 'falta', o limit 1;
    v_ate := greatest(public.agenda_somar_du(p_dia, -cf.congelamento_du), p_hoje);
    v_txt := format('se "%s" chegar até %s', coalesce(v_item ->> 'curto', 'o material'), public._dia_curto(v_ate));
  elsif p_tipo = 'conferir_material' then
    v_ate := greatest(public.agenda_somar_du(p_dia, -cf.congelamento_du), p_hoje);
    v_txt := format('se você disser até %s se tem peça a comprar', public._dia_curto(v_ate));
  else
    v_ate := greatest(public.agenda_somar_du(p_dia, -cf.congelamento_du), p_hoje);
    v_txt := format('se você confirmar os dias até %s', public._dia_curto(v_ate));
  end if;
  return jsonb_build_object('condicao', left(v_txt, 160), 'condicao_ate', v_ate);
end;
$function$;

comment on function public._agenda_condicao_da_reserva(uuid, text, date, jsonb, date) is
  'Agenda de Produção (Fase 2, P2): a condição da reserva em palavras e a data-limite, do 1º dia dela — compra: o "compre até" daquele início, agenda_somar_du(dia, −(folga_material_du + prazo da classe do fornecedor)) ou a compra combinada ("comprando hoje" quando já é hoje); material, conferir o material e os dias: o dia útil antes do congelamento. Nunca antes de hoje.';

-- ── 8. Aplicar, descartar, desfazer ────────────────────────────────────────────────────────────────────

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
  'Agenda de Produção (Fase 2, P2): aplica uma proposta, só com modo_proposta ligado (fora dele: "ainda está em teste", nada muda). Trava o plano; proposta fechada, vencida (expirada) ou de outra versão do plano (obsoleta; com p_via motor, refaz com os mesmos parâmetros e aplica a nova, uma vez) não aplica. agenda_validar não vazia = recusa com a lista. Itens: os das OS de p_os (todas, sem lista), sem os críticos — esses só com p_pergunta respondida (e então toda ação sai critica = true com pergunta_id). Cancelar → cancelada (o fixado com agenda.mexe_fixado); criar → publicada, fixada no congelado (congelamento) e no pedido do dono pela tela, aprovação ou *grava* (dono); o que não foi escolhido é apagado. Por OS: a porta (agendada quando tem dia; de volta quando ficou sem nenhum, aguardando peças se foi o material), o espelho das datas, a duração só sugerida que o dono pediu fica aceita, e uma linha em agenda_acoes (publicar/criar/mover/cancelar/promover_reserva/soltar_reserva) com antes/depois, a frase e o desfazer (desfazer_validade, até o 1º meio-dia começar; não na tela nem na aprovação). Vias: motor, vigia, conferencia, dono, tela, aprovacao.';

create or replace function public.agenda_descartar(p_proposta uuid, p_autor uuid default null, p_motivo text default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_estado text;
begin
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  select estado into v_estado from public.agenda_propostas where id = p_proposta for update;
  if not found then
    raise exception 'Não encontrei esse plano.' using errcode = 'P0002';
  end if;
  if v_estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Esse plano já está fechado.');
  end if;
  update public.agenda_propostas
     set estado = 'descartada', decidida_em = now(), decidida_por = p_autor, motivo_fim = left(coalesce(p_motivo, 'descartada'), 200)
   where id = p_proposta;
  delete from public.agenda_alocacoes where proposta_id = p_proposta and estado = 'proposta';
  return jsonb_build_object('ok', true, 'texto', 'Descartei esse plano: nada mudou na agenda.');
end;
$function$;

comment on function public.agenda_descartar(uuid, uuid, text) is
  'Agenda de Produção (Fase 2, P2): descarta uma proposta aberta (fica o registro, estado descartada) e apaga as alocações dela em estado proposta (nunca vigoraram).';

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
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você.").';

-- Qual mudança o dono quer desfazer: o nome ou o número da OS (a última dela), "semana" (a última publicação, com todas as
-- ações dela) ou nada (a única desfazível contada no último fechamento ou acorde; senão a única desfazível).
create or replace function public.agenda_acao_desfazivel(p_ref text, p_hoje date default public._hoje_brt(),
                                                         p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ref  text := btrim(coalesce(p_ref, ''));
  v_norm text := public._agenda_normal(p_ref);
  v_ids  uuid[];
  v_ro   jsonb;
  v_dia  date;
  v_prop uuid;
begin
  if v_norm in ('semana', 'a semana', 'da semana', 'semana toda', 'a semana toda') then
    select a.proposta_id into v_prop from public.agenda_acoes a
     where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo = 'publicar'
     order by a.criada_em desc, a.id desc limit 1;
    if v_prop is null then
      return jsonb_build_object('status', 'nenhuma', 'texto', 'Não tenho publicação da semana para desfazer agora.');
    end if;
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.proposta_id = v_prop and a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
                    order by a.criada_em, a.id);
    return jsonb_build_object('status', 'ok', 'acao_id', v_ids[1], 'acao_ids', to_jsonb(v_ids),
                              'texto', 'Desfaço a publicação da semana.');
  end if;
  if v_ref <> '' and v_norm not in ('a ultima', 'ultima', 'o ultimo', 'ultimo', 'isso', 'tudo') then
    v_ro := public.agenda_resolver_os(v_ref, p_hoje);
    if v_ro ->> 'status' <> 'ok' then
      return jsonb_build_object('status', coalesce(v_ro ->> 'status', 'nao_achei'), 'texto', v_ro ->> 'texto', 'opcoes', v_ro -> 'opcoes');
    end if;
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.service_order_id = (v_ro ->> 'id')::uuid and a.executada and a.desfeita_em is null
                      and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer'
                    order by a.criada_em desc, a.id desc limit 1);
    if cardinality(v_ids) = 0 then
      return jsonb_build_object('status', 'nenhuma',
               'texto', format('Não tenho mudança minha no %s para desfazer agora.', v_ro ->> 'cliente_curto'));
    end if;
    return jsonb_build_object('status', 'ok', 'acao_id', v_ids[1], 'acao_ids', to_jsonb(v_ids),
                              'texto', (select a.texto from public.agenda_acoes a where a.id = v_ids[1]));
  end if;
  -- sem nome: a última, se pediu; senão as contadas no último fechamento/acorde; senão todas as desfazíveis
  if v_norm in ('a ultima', 'ultima', 'o ultimo', 'ultimo') then
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer'
                    order by a.criada_em desc, a.id desc limit 1);
  else
    select max((a.contada_em at time zone 'America/Sao_Paulo')::date) into v_dia
      from public.agenda_acoes a
     where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer' and a.contada_em is not null;
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer'
                      and (v_dia is null or (a.contada_em at time zone 'America/Sao_Paulo')::date = v_dia)
                    order by a.criada_em, a.id);
  end if;
  if cardinality(v_ids) = 0 then
    return jsonb_build_object('status', 'nenhuma', 'texto', 'Não tenho mudança minha para desfazer agora.');
  end if;
  if cardinality(v_ids) = 1 then
    return jsonb_build_object('status', 'ok', 'acao_id', v_ids[1], 'acao_ids', to_jsonb(v_ids),
                              'texto', (select a.texto from public.agenda_acoes a where a.id = v_ids[1]));
  end if;
  return jsonb_build_object('status', 'ambiguo', 'acao_ids', to_jsonb(v_ids),
    'texto', format('Qual? %s Diga *desfaz* e o nome.',
                    (select string_agg(coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) || ' (' || rtrim(
                              regexp_replace(a.texto, '^[^:]*: ', ''), '.') || ')', ' ou ' order by a.criada_em, a.id)
                       from public.agenda_acoes a
                       left join public.service_orders so on so.id = a.service_order_id
                       left join public.clients cl on cl.id = so.client_id
                      where a.id = any (v_ids)) || '?'));
end;
$function$;

comment on function public.agenda_acao_desfazivel(text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): resolve o que o dono quer desfazer — o nome ou o número da OS (agenda_resolver_os: a última ação desfazível dela), "semana" (a última publicação: todas as ações dela em acao_ids), "a última", ou nada (a única desfazível contada no último fechamento ou acorde; senão a única desfazível). Mais de uma = {status ambiguo, texto "Qual? Nelson (…) ou Vanderlei (…)? Diga *desfaz* e o nome."}; nenhuma = "Não tenho mudança minha para desfazer agora.". {status ok|ambiguo|nenhuma|nao_achei, acao_id, acao_ids, texto}.';

-- ── 9. Marcar (o pedido do dono) e decidir (a resposta do dono) ────────────────────────────────────────

create or replace function public.agenda_marcar_os(p_autor uuid, p_os uuid, p_de date, p_ate date default null,
                                                   p_pessoa uuid default null, p_via text default 'tela', p_origem text default 'dono',
                                                   p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_ate   date := coalesce(p_ate, p_de);
  v_r     jsonb;
  v_s     jsonb;
  v_ap    jsonb;
  v_motivo text;
  v_dia   date;
  v_origem text;
begin
  if p_via is null or p_via not in ('dono', 'tela', 'aprovacao') then
    raise exception 'Caminho desconhecido para marcar: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_os is null or p_de is null or v_ate < p_de then
    raise exception 'Diga a OS e o dia.' using errcode = '22023';
  end if;
  cf := public._agenda_cfg();
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  if v_ate < p_hoje then
    return jsonb_build_object('ok', false, 'texto', 'Esse dia já passou: me diga outro.');
  end if;
  v_origem := case p_via when 'tela' then 'tela' when 'aprovacao' then 'aprovacao'
                         else case when p_origem in ('dono', 'assistente') then p_origem else 'dono' end end;
  v_r := public.agenda_propor('os', null, null, array[p_os],
           jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', p_os, 'de', p_de, 'ate', v_ate, 'pessoa', p_pessoa))),
           true, v_origem, v_autor, p_hoje, p_agora);
  if not coalesce((v_r ->> 'ok')::boolean, false) then
    return v_r;
  end if;
  if exists (select 1 from jsonb_array_elements(v_r -> 'itens') i
              where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = p_os and i ->> 'tipo' <> 'reserva') then
    v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, p_via, v_autor, null, p_hoje, p_agora);
    -- o dia pedido antes de o material estar garantido fica (é a decisão do dono); o aviso já está no texto ("— mas …")
    -- e vai à parte para a tela
    return v_ap || jsonb_build_object('proposta_id', v_r ->> 'proposta_id',
      'aviso_material', (select i ->> 'aviso_material' from jsonb_array_elements(v_r -> 'itens') i
                          where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = p_os and i ->> 'aviso_material' is not null limit 1));
  end if;
  -- Não cabe no dia pedido: o motivo e o 1º dia que o motor acha sem o pedido.
  perform public.agenda_descartar((v_r ->> 'proposta_id')::uuid, v_autor, 'não coube no dia pedido');
  v_motivo := (select f ->> 'texto' from jsonb_array_elements(v_r -> 'fora') f where (f ->> 'os')::uuid = p_os limit 1);
  v_s := public.agenda_propor('os', null, null, array[p_os], '{}'::jsonb, false, v_origem, v_autor, p_hoje, p_agora);
  v_dia := (select min((i ->> 'de')::date) from jsonb_array_elements(v_s -> 'itens') i
             where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = p_os and i ->> 'tipo' <> 'reserva');
  return jsonb_build_object('ok', false, 'primeiro_dia', v_dia,
    'texto', coalesce(public._agenda_maiuscula(regexp_replace(coalesce(v_motivo, ''), '^[^:]*: ', '')), '')
             || case when v_motivo is null then format('Não cabe %s.', public._dia_curto(p_de)) else '' end
             || case when v_dia is not null then format(' O primeiro dia que dá é %s.', public._dia_curto(v_dia))
                     else ' Não achei outro dia nas próximas semanas com a equipe de hoje.' end);
end;
$function$;

comment on function public.agenda_marcar_os(uuid, uuid, date, date, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): o "marcar para tal dia" do dono — da tela (Agendar OS), da aprovação com PIN e do *grava* de um pedido no chat. Só com modo_proposta ligado. agenda_propor(os, fixar: começo entre p_de e p_ate, com p_pessoa se dito) + agenda_aplicar (fixada pelo dono; não é crítico: é a decisão dele). O dia antes de o material estar garantido é marcado, com o aviso no texto ("— mas "Compressor" só chega por volta de ter 06/10 (pronto qua 07/10)") e em aviso_material. Não cabe →"Não cabe qui 29/10: o Roberto já está no Vanderlei. O primeiro dia que dá é sex 30/10." (o dia que o motor acha sem o pedido). Admin pelo _autor_da_agenda.';

create or replace function public.agenda_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid default null,
                                                 p_via text default 'whatsapp', p_trecho text default null,
                                                 p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_q    public.agenda_perguntas%rowtype;
  v_opc  jsonb;
  v_rest jsonb;
  v_sim  jsonb;
  v_mud  text;
  v_r    jsonb;
  v_ap   jsonb;
begin
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  if not v_q.critica then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta não é de decisão.');
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  v_rest := coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb);

  -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
  -- volta com os dias de agora (nada é executado).
  if v_q.versao_base is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
     and v_opc -> 'espera' <> '{}'::jsonb then
    v_sim := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest, false, 'dono', p_autor, p_hoje, p_agora);
    select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                             coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
      into v_mud
      from jsonb_each(v_opc -> 'espera') e
      left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                          where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
     where x.fim is distinct from (e.value #>> '{}')::date;
    if v_mud is not null then
      return jsonb_build_object('ok', false, 'mudou', true,
        'texto', 'A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.');
    end if;
  end if;

  begin
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = p_pergunta;
    v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta),
                                true, 'dono', p_autor, p_hoje, p_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'dono', p_autor, p_pergunta, p_hoje, p_agora);
    if not coalesce((v_ap ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_ap ->> 'texto', 'não deu');
    end if;
  exception when sqlstate 'P0098' then
    -- nada fica: a pergunta continua aberta
    return jsonb_build_object('ok', false, 'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
  end;
  return jsonb_build_object('ok', true, 'texto', 'Feito: ' || (v_ap ->> 'texto'), 'acoes', v_ap -> 'acoes',
                            'proposta_id', v_r ->> 'proposta_id');
end;
$function$;

comment on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): a resposta do dono a uma pergunta crítica aberta (só em ligado). Opção que não existe = recusa, nada marcado. Se a agenda mudou desde a pergunta, o efeito da opção é refeito agora e, se não termina como a opção dizia (espera), devolve a pergunta com os dias de agora sem executar. Senão: a pergunta fica respondida (opcao_escolhida, resposta = as palavras do dono, respondida_*) e o efeito é executado — agenda_propor(replano, as OS da pergunta, as restrições da opção + decisao) e agenda_aplicar com p_pergunta (toda ação sai critica = true com pergunta_id). Falhou = nada fica, a pergunta continua aberta. Canais: whatsapp, painel, tela.';

-- O que a pessoa tem no plano num dia (para o registrar_diaria sugerir a OS). Só com modo_proposta ligado.
create or replace function public.agenda_os_do_dia(p_payee uuid, p_dia date)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select case when (public._agenda_cfg()).modo_proposta <> 'ligado' then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object('os', x.os, 'numero', x.numero, 'cliente_curto', x.cliente_curto,
                                        'turnos', x.turnos, 'tipo', x.tipo, 'reserva', x.reserva) order by x.inicio, x.numero)
      from (select a.service_order_id as os, so.service_order_number as numero, public._agenda_nome_curto(cl.name) as cliente_curto,
                   to_jsonb(array_agg(distinct a.turno order by a.turno)) as turnos, min(a.tipo) as tipo,
                   bool_and(a.tipo = 'reserva') as reserva, min(lower(a.periodo)) as inicio
              from public.agenda_alocacoes a
              join public.service_orders so on so.id = a.service_order_id
              left join public.clients cl on cl.id = so.client_id
             where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada')
             group by a.service_order_id, so.service_order_number, cl.name) x), '[]'::jsonb) end;
$function$;

comment on function public.agenda_os_do_dia(uuid, date) is
  'Agenda de Produção (Fase 2, P2): as OS do plano vigente de uma pessoa num dia — [{os, numero, cliente_curto, turnos [manha, tarde], tipo, reserva}]. Só com modo_proposta ligado (fora dele, []). Para o registrar_diaria sugerir a OS do dia.';

-- ── Portas ──────────────────────────────────────────────────────────────────────────────────────────────
-- As leituras: authenticated (o painel) e service_role, nunca anon. O motor (que grava) só service_role; marcar também
-- authenticated, com o administrador conferido dentro. As peças internas do encaixe: só service_role.
revoke all on function
  public._agenda_ultima_evidencia(uuid, date), public._agenda_plano_da_os(uuid, date), public.os_prontidao(uuid, date),
  public.agenda_meios_da_os(uuid, date), public.agenda_grade(date, date, date, uuid[]),
  public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean), public._agenda_dia_sem_mes(date),
  public._agenda_dias_texto(date[]), public._agenda_meio_texto(date, text), public._agenda_faixa_texto(date, text, date, text),
  public._agenda_rotulo_da_os(uuid), public._agenda_pessoas_texto(jsonb, uuid), public._agenda_criticidade(uuid, date, date, date, date, date, uuid[], uuid[]),
  public._agenda_itens_escolhidos(jsonb, uuid[], uuid), public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb),
  public.agenda_validar(uuid, uuid[], date, timestamptz, uuid), public.agenda_acao_desfazivel(text, date, timestamptz),
  public.agenda_os_do_dia(uuid, date), public._agenda_condicao_da_reserva(uuid, text, date, jsonb, date),
  public._agenda_aviso_do_material(jsonb, text, text, date)
  from public, anon;
grant execute on function
  public._agenda_ultima_evidencia(uuid, date), public._agenda_plano_da_os(uuid, date), public.os_prontidao(uuid, date),
  public.agenda_meios_da_os(uuid, date), public.agenda_grade(date, date, date, uuid[]),
  public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean), public._agenda_dia_sem_mes(date),
  public._agenda_dias_texto(date[]), public._agenda_meio_texto(date, text), public._agenda_faixa_texto(date, text, date, text),
  public._agenda_rotulo_da_os(uuid), public._agenda_pessoas_texto(jsonb, uuid), public._agenda_criticidade(uuid, date, date, date, date, date, uuid[], uuid[]),
  public._agenda_itens_escolhidos(jsonb, uuid[], uuid), public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb),
  public.agenda_validar(uuid, uuid[], date, timestamptz, uuid), public.agenda_acao_desfazivel(text, date, timestamptz),
  public.agenda_os_do_dia(uuid, date), public._agenda_condicao_da_reserva(uuid, text, date, jsonb, date),
  public._agenda_aviso_do_material(jsonb, text, text, date)
  to authenticated, service_role;

revoke all on function
  public._agenda_ints(jsonb), public._agenda_bools(jsonb),
  public._agenda_contexto(date, date, date, uuid[], uuid[]),
  public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer),
  public._agenda_ocupar(jsonb, integer[], jsonb, integer, boolean, integer[], integer[], integer[], integer[], integer[]),
  public._agenda_melhor(jsonb, jsonb),
  public._agenda_melhor_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, integer, integer, boolean),
  public._agenda_so_diaristas(jsonb, integer), public._agenda_encaixar(jsonb, jsonb, jsonb), public._agenda_ctx_com(jsonb, jsonb),
  public._agenda_por_que_nao(jsonb, jsonb, integer, integer), public._agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date),
  public._agenda_alocs_do_bloco(jsonb, jsonb),
  public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz),
  public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz), public.agenda_descartar(uuid, uuid, text),
  public.agenda_desfazer(uuid, uuid, text, date, timestamptz),
  public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)
  from public, anon, authenticated;
grant execute on function
  public._agenda_ints(jsonb), public._agenda_bools(jsonb),
  public._agenda_contexto(date, date, date, uuid[], uuid[]),
  public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer),
  public._agenda_ocupar(jsonb, integer[], jsonb, integer, boolean, integer[], integer[], integer[], integer[], integer[]),
  public._agenda_melhor(jsonb, jsonb),
  public._agenda_melhor_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, integer, integer, boolean),
  public._agenda_so_diaristas(jsonb, integer), public._agenda_encaixar(jsonb, jsonb, jsonb), public._agenda_ctx_com(jsonb, jsonb),
  public._agenda_por_que_nao(jsonb, jsonb, integer, integer), public._agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date),
  public._agenda_alocs_do_bloco(jsonb, jsonb),
  public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz),
  public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz), public.agenda_descartar(uuid, uuid, text),
  public.agenda_desfazer(uuid, uuid, text, date, timestamptz),
  public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)
  to service_role;

revoke all on function public.agenda_marcar_os(uuid, uuid, date, date, uuid, text, text, date, timestamptz) from public, anon;
grant execute on function public.agenda_marcar_os(uuid, uuid, date, date, uuid, text, text, date, timestamptz)
  to authenticated, service_role;
