-- Agenda de Produção, correção de 29/10 (pacote P5): a rodada da vigia no limite de tempo.
-- (1 parâmetro novo em agenda_config; 6 funções novas, só de dentro da vigia; 2 recriadas; nenhum dado muda)
--
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/p5c/montar-migration.mjs. As 2 recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* dos pacotes P1 a P4, que não
-- as recriam): os_prontidao de 20261029100900 e agenda_vigiar de 20261025100300. As mudanças estão só nos blocos
-- "-- CORREÇÃO 29/10 (P5): … -- CORREÇÃO 29/10 (P5): fim"; fora deles nenhuma linha muda (o K de
-- supabase/tests/agenda_correcao_2910_p5.sql confere).
--
-- ═══ POR QUE ═══ (auditoria de 29/10, leitor "entrega"; medido de novo em produção, só com SELECT, em 30/10)
--   · A rodada da vigia levava de 1,6 a 7,7 s (mediana 2,6 s, 120 rodadas em 48 h) contra o limite de 8 s, e estourou às
--     07:30 e às 23:00 de 29/10 ("canceling statement due to statement timeout" em app_error_logs, task-automations,
--     agenda:vigia; a rodada desses dois tiques não ficou gravada). As outras rotinas do tique são curtas: material ~0,6 s,
--     rotina ~0,1 s, cliente ~0,2 s (até 1,7 s).
--   · O limite: o papel authenticator do PostgREST tem statement_timeout = 8s (e lock_timeout = 8s); o service_role não tem
--     valor próprio, então toda RPC do task-automations (supabase-js, sem tempo próprio na chamada) tem 8 s.
--   · Em tiques iguais (o mesmo trabalho, as mesmas contagens) o tempo variava 3 vezes: às :00 e às :30 a vigia disputa a
--     máquina com outras tarefas (dropbox-indice e email-imap de 10 em 10 min, ai-whatsapp-followups de 30 em 30, o resumo
--     da manhã às 07:30 e o fechamento às 17:30). A rodada não controla a disputa; o que dá para cortar é o trabalho dela.
--   · O trabalho: a prontidão (os_prontidao, de 12 a 240 ms por OS em produção) era recalculada para a mesma OS em cada
--     passo (limpeza, material, chegou, parada, duração, fila...): ~37 contas por rodada para as 11 OS da carteira. E dentro
--     de cada uma o prazo do fornecedor (_agenda_prazo_do_fornecedor, ~6 ms em produção) saía ~25 vezes por item, porque o
--     planejador desmanchava o passo 6 da conta do material e copiava a chamada para cada uso (a classe, os dias úteis, os
--     corridos, o texto, a dúvida): 1.323 contas por rodada na carteira de hoje, para 18 itens.
--
-- ═══ O QUE MUDA ═══
--   1. os_prontidao, a barreira (offset 0 no passo 6): o prazo do fornecedor uma vez por item. Vale para toda leitura (a
--      tela, o *agenda*, o fechamento das 17:30, o aviso do gestor), não só a vigia. O resultado é o mesmo, byte a byte.
--   2. A memória da rodada: agenda_vigiar a abre (agenda.rodada = o dia), e dentro dela a prontidão de cada OS é calculada
--      uma vez e lembrada enquanto a transação não grava nada no que ela lê. Quem diz se algo foi gravado é a marca
--      (_agenda_rodada_marca): os contadores da própria transação (linhas inseridas, mudadas e apagadas) nas tabelas de
--      public, menos as 5 que a vigia escreve e a prontidão não lê (a pergunta, a ação, a proposta, a linha da rodada, o
--      erro). A memória mora em variáveis da transação (nada em tabela), fecha no fim da rodada e nenhuma outra sessão a vê.
--      Num tique sem nada, 11 contas no lugar de 37.
--   3. A linha da rodada (agenda_vigia_rodadas.contagens) guarda ms (o tempo de cada passo) e memoria ({ligada, calculadas,
--      lembradas}). O que a vigia devolve ao task-automations não muda.
--   4. agenda_config.vigia_memoria (true): false desliga a memória sem migration (cada passo recalcula, como antes).
--   Não muda: o que a vigia decide e grava (provado na bancada: com e sem a memória, o mesmo retrato de tudo o que ela
--   grava, numa semana de tiques da carteira de hoje, na da Fase 6 e na promoção da reserva do Lenine); agenda_meios_da_os
--   (lembrar os meios-dias não pagava a conta: medido); o limite de 8 s (a causa não era legítima, era conta repetida); o
--   task-automations e o aviso do gestor (P4), que ficam mais rápidos sem mudar (a mesma prontidão).
--
-- ═══ O GANHO (bancada; mediana de 3 depois de aquecer; antes = as migrations até 20261030100300) ═══
--   carteira de hoje (as 11 OS de produção): vigia qui 16:30, que publica, 1.123 → 572 ms; qui 17:00 704 → 193 ms; ter 10:00
--     491 → 157 ms; aviso do gestor 16:45 222 → 100 ms; fechamento 227 → 119 ms.
--   carteira da Fase 6 (a mais cheia): vigia qui 16:30 2.983 → 928 ms; qui 17:00 1.986 → 511 ms; ter 10:00 1.654 → 393 ms;
--     aviso 382 → 119 ms; fechamento 463 → 144 ms.
--   Produção leva ~3,4 vezes a bancada nesta conta (qui 17:00: 704 ms aqui, ~2,4 a 2,9 s lá fora de disputa): a rodada sem
--   nada deve cair de ~2,5 s para ~0,7 s e, com a disputa das :00 e das :30 (até 3 vezes), ficar perto de 2 s.
--
-- ═══ O QUE MEDIR EM PRODUÇÃO DEPOIS (só SELECT) ═══
--   a) o tempo: select rotina, count(*), percentile_disc(0.5) within group (order by duracao_ms), max(duracao_ms)
--        from agenda_vigia_rodadas where p_agora > <a hora da aplicação> group by rotina;
--      esperado: vigia com mediana abaixo de 1 s e máximo abaixo de 3 s; a quinta 16:30 (a publicação) é a mais pesada.
--   b) a memória: contagens -> 'memoria' — num tique sem nada, calculadas = as OS da carteira e lembradas > 0; calculadas bem
--      maior só no tique que gravou alguma coisa. ligada = false em todos = vigia_memoria desligada (ou track_counts).
--   c) o passo que pesa: contagens -> 'ms' (o material e as violações são os maiores na bancada); um passo acima de 1 s com
--      frequência é o próximo a olhar.
--   d) nenhum 57014 em app_error_logs (task-automations agenda:vigia, ai-daily-briefing tarde:agenda) e nenhum tique de 15
--      min sem a linha da vigia em agenda_vigia_rodadas.
--
-- Ordem de ligar: depois das 20261030100000 a 100300 (P1 a P4). Não precisa de deploy de edge function. Aplicar com o OK
-- nomeado do dono. Prova: supabase/tests/agenda_correcao_2910_p5.sql (bancada).
--
-- DESFAZER: update public.agenda_config set vigia_memoria = false where id;   (a memória desliga no tique seguinte)
--   Para tirar tudo: recriar os_prontidao com o corpo de 20261029100900 e agenda_vigiar com o de 20261025100300. As 6 funções
--   novas e a coluna podem ficar (ninguém as usa sem as recriadas).
--
-- IDEMPOTENTE: add column if not exists, create or replace function, revoke e comment.

-- ── 1. O interruptor ─────────────────────────────────────────────────────────────────────────────────────────
alter table public.agenda_config add column if not exists vigia_memoria boolean not null default true;

comment on column public.agenda_config.vigia_memoria is
  'Agenda de Produção (correção de 29/10, P5): true = dentro da rodada da vigia a prontidão de cada OS é calculada uma vez e lembrada enquanto nada do que ela lê é gravado (o resultado é o mesmo). false = cada passo recalcula, como antes de 30/10 (o interruptor para desfazer sem migration).';

-- ── 2. A memória da rodada (6 funções novas, só para dentro da vigia) ──────────────────────────────────────────
-- Onde mora: em variáveis da transação (set_config local), nunca em tabela: some no fim da transação e nenhuma outra sessão
-- a vê. agenda.rodada = o dia da rodada (vazio = desligada; 'calculando' = a conta de dentro, com a memória em pausa);
-- agenda.rodada_pront = {os: {m: a marca, v: a prontidão}}; agenda.rodada_conta = quantas contas a memória fez
-- (calculadas) e poupou (lembradas).

-- A marca das escritas da transação: quantas linhas ela já inseriu, mudou ou apagou nas tabelas de public (os contadores
-- da própria transação, pg_stat_get_xact_*; contam até o que uma subtransação desfez, então só crescem). A mesma marca =
-- nada foi gravado desde então, e a prontidão lembrada é a que a conta daria agora. Todas as tabelas de public, de
-- propósito (as 23 que a prontidão lê estão nelas, e uma leitura nova que alguém acrescente também), MENOS as 5 que a vigia
-- escreve e a prontidão não lê: a pergunta, a ação, a proposta, a linha da rodada e o registro de erro. O G de
-- supabase/tests/agenda_correcao_2910_p5.sql prova que nenhuma função da conta da prontidão lê alguma delas; se um dia
-- ler, o teste cai e a tabela sai desta lista.
create or replace function public._agenda_rodada_marca()
 returns bigint
 language sql
 volatile
 set search_path to 'public'
as $function$
  select coalesce(sum(pg_catalog.pg_stat_get_xact_tuples_inserted(c.oid) + pg_catalog.pg_stat_get_xact_tuples_updated(c.oid)
                      + pg_catalog.pg_stat_get_xact_tuples_deleted(c.oid)), 0)::bigint
    from pg_catalog.pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
     and c.relname not in ('agenda_perguntas', 'agenda_acoes', 'agenda_propostas', 'agenda_vigia_rodadas', 'app_error_logs');
$function$;

-- Conta uma chamada da memória (calculadas ou lembradas), para a linha da rodada.
create or replace function public._agenda_rodada_contar(p_chave text)
 returns void
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v jsonb := coalesce(nullif(current_setting('agenda.rodada_conta', true), '')::jsonb, '{}'::jsonb);
begin
  perform set_config('agenda.rodada_conta',
                     jsonb_set(v, array[p_chave], to_jsonb(coalesce((v ->> p_chave)::int, 0) + 1))::text, true);
end;
$function$;

-- Abre a rodada (p_hoje = o dia dela; null = memória desligada) com a memória vazia. Sem os contadores da transação
-- (track_counts desligado) a marca não andaria: a memória não abre.
create or replace function public._agenda_rodada_abrir(p_hoje date)
 returns boolean
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_liga boolean := p_hoje is not null and coalesce(current_setting('track_counts', true), 'off') = 'on';
begin
  perform set_config('agenda.rodada', case when v_liga then p_hoje::text else '' end, true);
  perform set_config('agenda.rodada_pront', '{}', true);
  perform set_config('agenda.rodada_conta', '{}', true);
  return v_liga;
end;
$function$;

-- Fecha a rodada: esvazia a memória (o resto da transação calcula como sempre) e devolve o que ela fez:
-- {ligada, calculadas, lembradas}.
create or replace function public._agenda_rodada_fechar()
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v jsonb := jsonb_build_object('ligada', coalesce(current_setting('agenda.rodada', true), '') not in ('', 'calculando'))
             || coalesce(nullif(current_setting('agenda.rodada_conta', true), '')::jsonb, '{}'::jsonb);
begin
  perform set_config('agenda.rodada', '', true);
  perform set_config('agenda.rodada_pront', '', true);
  perform set_config('agenda.rodada_conta', '', true);
  return v;
end;
$function$;

-- A prontidão que a rodada lembra da OS, ou null: nunca calculou, ou a transação gravou alguma coisa depois da conta (a
-- marca andou).
create or replace function public._agenda_rodada_lembrar(p_os uuid)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  e jsonb := nullif(current_setting('agenda.rodada_pront', true), '')::jsonb -> p_os::text;
begin
  if e is null or (e ->> 'm')::bigint is distinct from public._agenda_rodada_marca() then
    return null;
  end if;
  perform public._agenda_rodada_contar('lembradas');
  return e -> 'v';
end;
$function$;

-- Guarda a prontidão da OS com a marca de quando a conta começou.
create or replace function public._agenda_rodada_guardar(p_os uuid, p_marca bigint, p_valor jsonb)
 returns void
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
begin
  perform set_config('agenda.rodada_pront',
                     (coalesce(nullif(current_setting('agenda.rodada_pront', true), '')::jsonb, '{}'::jsonb)
                      || jsonb_build_object(p_os::text, jsonb_build_object('m', p_marca, 'v', p_valor)))::text, true);
  perform public._agenda_rodada_contar('calculadas');
end;
$function$;

comment on function public._agenda_rodada_marca() is
  'Agenda de Produção (correção de 29/10, P5): a marca das escritas desta transação nas tabelas de public (linhas inseridas, mudadas e apagadas, pelos contadores da própria transação; só cresce), menos as 5 que a vigia escreve e a conta da prontidão não lê (agenda_perguntas, agenda_acoes, agenda_propostas, agenda_vigia_rodadas, app_error_logs). A memória da rodada da vigia só devolve o que foi calculado com a marca de agora.';
comment on function public._agenda_rodada_contar(text) is
  'Agenda de Produção (correção de 29/10, P5): conta uma chamada da memória da rodada (calculadas ou lembradas), para a linha da rodada.';
comment on function public._agenda_rodada_abrir(date) is
  'Agenda de Produção (correção de 29/10, P5): a vigia abre a memória da rodada (agenda.rodada = o dia; null = desligada; sem track_counts não abre). Dentro dela os_prontidao de cada OS é calculada uma vez e lembrada enquanto a transação não grava nada no que a prontidão lê.';
comment on function public._agenda_rodada_fechar() is
  'Agenda de Produção (correção de 29/10, P5): fecha a memória da rodada (esvazia as variáveis; o resto da transação calcula como sempre) e devolve {ligada, calculadas, lembradas} para a linha da rodada.';
comment on function public._agenda_rodada_lembrar(uuid) is
  'Agenda de Produção (correção de 29/10, P5): a prontidão lembrada da OS se a marca das escritas da transação é a mesma de quando foi calculada; senão null (calcular de novo).';
comment on function public._agenda_rodada_guardar(uuid, bigint, jsonb) is
  'Agenda de Produção (correção de 29/10, P5): guarda na memória da rodada a prontidão da OS com a marca de quando a conta começou.';

-- ── 3. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- CORREÇÃO 29/10 (P5):") ──────────
-- Fora dos blocos nenhuma linha muda (o K de supabase/tests/agenda_correcao_2910_p5.sql confere). Quem recriar de novo
-- qualquer uma delas copia DESTA migration.

-- os_prontidao (de 20261029100900_agenda_fase6_correcao_calculo.sql)
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
  -- CORREÇÃO FASE 6: (C1) item 1: o início pelo material pelo dia DITO (o que julga o que já está publicado)
  v_dpm_dito    date;
  v_inicio_dito date;
  -- CORREÇÃO FASE 6: fim
  -- CORREÇÃO 29/10 (P5): a memória da rodada da vigia
  v_memo        jsonb;
  v_marca       bigint;
  -- CORREÇÃO 29/10 (P5): fim
begin
  if p_hoje is null then
    raise exception 'os_prontidao: sem o dia de hoje' using errcode = '22004';
  end if;
  -- CORREÇÃO 29/10 (P5): dentro da rodada da vigia (agenda.rodada = o dia dela, posto por agenda_vigiar), a prontidão de
  -- cada OS é calculada UMA vez e lembrada enquanto a transação não gravar nada no que ela lê (_agenda_rodada_marca).
  -- Antes, a mesma OS era recalculada em cada passo (limpeza, material, chegou, parada, duração, fila...): ~37 contas por
  -- rodada para 11 OS. O cálculo é o de sempre (a chamada de dentro, com a memória em pausa); fora da rodada, nada muda.
  if p_so_id is not null and current_setting('agenda.rodada', true) = p_hoje::text then
    v_memo := public._agenda_rodada_lembrar(p_so_id);
    if v_memo is null then
      v_marca := public._agenda_rodada_marca();
      perform set_config('agenda.rodada', 'calculando', true);
      v_memo := public.os_prontidao(p_so_id, p_hoje);
      perform set_config('agenda.rodada', p_hoje::text, true);
      perform public._agenda_rodada_guardar(p_so_id, v_marca, v_memo);
    end if;
    return v_memo;
  end if;
  -- CORREÇÃO 29/10 (P5): fim

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
       -- FASE 4: a linha ligada a um item de texto livre da conta já está nele, no grupo 1 (os_necessidade_bruta, P2).
       and not exists (select 1 from bruto b where b.origin = 'free_text' and b.src = poi.service_order_service_id)
       -- FASE 4: fim
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
                    -- FASE 4: o item de texto livre é coberto pela linha da OC ligada a ele (service_order_service_id, P2).
                    when q.origem = 'texto_livre' then v.service_order_service_id = q.vinculo
                    -- FASE 4: fim
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
    -- FASE 4: o prazo do fornecedor numa fonte só (_agenda_prazo_do_fornecedor: o que o dono disse, o cadastro repetido,
    -- o nome e a cidade/UF tolerante ao caractere quebrado); a classe, os dias úteis e os corridos saem dele no passo 7.
    select q.*, public._agenda_prazo_do_fornecedor(q.forn_id) as pf
    -- FASE 4: fim
      from passo5 q
    -- CORREÇÃO 29/10 (P5): o prazo do fornecedor uma vez por item. Sem esta barreira o planejador desmanchava o passo 6 nos de
    -- cima e copiava a chamada para cada uso de pf (a classe, os dias úteis, os corridos, o texto, a dúvida): ~25 contas de
    -- _agenda_prazo_do_fornecedor por item (~6 ms cada em produção). O resultado é o mesmo, byte a byte.
    offset 0
    -- CORREÇÃO 29/10 (P5): fim
  ),
  passo7 as (
    -- FASE 4: a classe e os dias úteis do fornecedor; o importado tem os dias corridos (e prazo nulo).
    select q.*, q.pf ->> 'classe' as classe, (q.pf ->> 'du')::int as prazo, (q.pf ->> 'corridos')::int as corridos
    -- FASE 4: fim
      from passo6 q
  ),
  passo8 as (
    select q.*,
           case
             when q.sit = 'na_mao' then 'A'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null and q.prev_fonte <> 'dono' then 'B'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then 'C'
             when q.sit in ('comprado', 'a_caminho') then 'D'
             -- FASE 4: o importado tem prazo (em dias corridos).
             when q.prazo is not null or q.corridos is not null then 'D'
             -- FASE 4: fim
             else 'E' end as nivel,
           case
             when q.sit = 'na_mao' then q.chegou_em
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then q.prev_ate
             -- FASE 4: a chegada pelo prazo do fornecedor (_agenda_chegada_pela_classe: dias úteis; o importado, os dias
             -- corridos levados ao dia útil).
             when q.sit in ('comprado', 'a_caminho') and (q.prazo is not null or q.corridos is not null) then
               public._agenda_chegada_pela_classe(q.classe, q.prazo, q.corridos, coalesce(q.comprado_em, p_hoje))
             when q.sit = 'falta' and (q.prazo is not null or q.corridos is not null) then
               -- "Se comprar hoje" (ou no dia combinado): calculado, nunca gravado.
               public._agenda_chegada_pela_classe(q.classe, q.prazo, q.corridos,
                                                  greatest(coalesce(q.compra_prevista_em, p_hoje), p_hoje))
             -- FASE 4: fim
           end as data,
           -- FASE 4: "compre até" pelo mesmo prazo; o importado: o início menos a folga, menos os dias corridos, no último dia
           -- útil até ali (agenda_somar_du(x + 1, -1) é o último dia útil até x).
           case when q.sit = 'falta' and q.prazo is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(v_est_sm, -(c.folga_material_du + q.prazo))
                when q.sit = 'falta' and q.corridos is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(public.agenda_somar_du(v_est_sm, -c.folga_material_du) - q.corridos + 1, -1) end as compre_ate,
           -- FASE 4: fim
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
           -- FASE 4: o texto do prazo do fornecedor ("entrega local, 1 dia útil (pela cidade, chute meu)"), a dúvida do
           -- cadastro (duplicado | sem_lugar) e os dias corridos do importado.
           'prazo_texto', q.pf ->> 'texto', 'duvida', q.pf ->> 'duvida', 'corridos', q.corridos,
           -- FASE 4: fim
           'comprado_em', q.comprado_em, 'compra_prevista_em', q.compra_prevista_em,
           'compre_ate', q.compre_ate,
           'atrasado', q.sit in ('comprado', 'a_caminho') and q.data is not null and q.data < p_hoje,
           'sem_data', q.nivel = 'E' or (q.nivel = 'D' and q.data is null))
           -- FASE 6: (P3) a data provável do material (spec-fase6 §5.3), só no nível B (a previsão de quem vende: OC, nota,
           -- fornecedor, Pix) e só enquanto o dia dito não chegou: data = o dia dito + o atraso medido do fornecedor em uso
           -- (_agenda_aprendido: só com modo_aprendizado ligado e fornecedor na lista); data_dita = o dia dito (o fato). O
           -- atrasado e o sem_data continuam pelo dia dito (a "chegou?" é no dia da previsão); C, A, D e E não mudam. Sem
           -- atraso em uso, o item é o de antes, byte a byte.
           || case when q.nivel = 'B' and q.forn_id is not null and q.data > p_hoje then
                coalesce((select jsonb_build_object(
                            'data', public.agenda_somar_du(q.data, x.du), 'data_dita', q.data,
                            'data_texto', case when q.sit <> 'na_mao' and q.disp_ef > 0 and q.disp_ef < q.req
                                               then format('%s de %s na mão, %s %s: ', replace(trim_scale(q.disp_ef)::text, '.', ','),
                                                           replace(trim_scale(q.req)::text, '.', ','),
                                                           case when q.req - q.disp_ef = 1 then 'falta' else 'faltam' end,
                                                           replace(trim_scale(q.req - q.disp_ef)::text, '.', ','))
                                               else '' end
                                          || format('%s %s; %s costuma atrasar até %s: conto com %s',
                                                    case q.prev_fonte when 'oc' then 'a OC diz' when 'nfe' then 'a nota diz'
                                                                      when 'fornecedor' then 'o fornecedor disse'
                                                                      when 'pix' then 'pelo Pix, chega' else 'a previsão é' end,
                                                    public._dia_curto(q.data),
                                                    coalesce(public._agenda_nome_curto(q.forn_cadastro), 'o fornecedor'),
                                                    public._agenda_aprendizado_valor('fornecedor_atraso', x.du),
                                                    public._dia_curto(public.agenda_somar_du(q.data, x.du))))
                            from (select public._agenda_aprendido('fornecedor_atraso', q.forn_id::text)::int as du) x
                           where x.du > 0), '{}'::jsonb)
              else '{}'::jsonb end
           -- FASE 6: fim
           -- CORREÇÃO FASE 6: (C1) itens 2 e 8 (a contagem dupla e o fornecedor inativo): o bloco da Fase 6 logo acima não vale
           -- mais — as 3 chaves dele saem ("- array[…]" pega só ele: o "-" vem antes do "||") — e vale este, que é ele com duas
           -- mudanças: (item 2) a previsão da nota (nfe) já é "quando sai + quanto leva" (o prazo da classe ou o medido): não
           -- ganha o atraso do fornecedor por cima; (item 8) o atraso é lido pela chave da medida (_agenda_fornecedor_da_medida:
           -- o cadastro inativo pelo principal). Sem atraso em uso, nada muda: o item é o de antes, byte a byte.
           - array['data', 'data_dita', 'data_texto']
           || case when q.nivel = 'B' and q.forn_id is not null and q.data > p_hoje and q.prev_fonte is distinct from 'nfe' then
                coalesce((select jsonb_build_object(
                            'data', public.agenda_somar_du(q.data, x.du), 'data_dita', q.data,
                            'data_texto', case when q.sit <> 'na_mao' and q.disp_ef > 0 and q.disp_ef < q.req
                                               then format('%s de %s na mão, %s %s: ', replace(trim_scale(q.disp_ef)::text, '.', ','),
                                                           replace(trim_scale(q.req)::text, '.', ','),
                                                           case when q.req - q.disp_ef = 1 then 'falta' else 'faltam' end,
                                                           replace(trim_scale(q.req - q.disp_ef)::text, '.', ','))
                                               else '' end
                                          || format('%s %s; %s costuma atrasar até %s: conto com %s',
                                                    case q.prev_fonte when 'oc' then 'a OC diz' when 'nfe' then 'a nota diz'
                                                                      when 'fornecedor' then 'o fornecedor disse'
                                                                      when 'pix' then 'pelo Pix, chega' else 'a previsão é' end,
                                                    public._dia_curto(q.data),
                                                    coalesce(public._agenda_nome_curto(q.forn_cadastro), 'o fornecedor'),
                                                    public._agenda_aprendizado_valor('fornecedor_atraso', x.du),
                                                    public._dia_curto(public.agenda_somar_du(q.data, x.du))))
                            from (select public._agenda_aprendido('fornecedor_atraso',
                                                                 public._agenda_fornecedor_da_medida(q.forn_id)::text)::int as du) x
                           where x.du > 0), '{}'::jsonb)
              else '{}'::jsonb end
           -- CORREÇÃO FASE 6: fim
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
    -- CORREÇÃO FASE 6: (C1) item 1: com a data provável em uso (algum crítico com data_dita), o início pelo material também
    -- pelo dia DITO (a chegada que o fornecedor, a OC, a nota ou o Pix disseram + folga_material_du). É por ele que
    -- _agenda_violacoes julga o que já está publicado: a data provável só encaixa o que é novo.
    if exists (select 1 from jsonb_array_elements(v_crit) e where e ? 'data_dita') then
      select max(coalesce(e ->> 'data_dita', e ->> 'data')::date) into v_dpm_dito
        from jsonb_array_elements(v_crit) e
       where e ->> 'nivel' <> 'A';
      v_inicio_dito := case when v_dpm_dito is not null then public.agenda_somar_du(v_dpm_dito, c.folga_material_du) end;
    end if;
    -- CORREÇÃO FASE 6: fim
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
                            -- FASE 4: a chegada "comprando hoje" pelo mesmo prazo do fornecedor (o importado em corridos).
                            public._dia_curto(public._agenda_chegada_pela_classe(v_compra ->> 'classe', (v_compra ->> 'prazo_du')::int,
                                                                                 (v_compra ->> 'corridos')::int, p_hoje)))
                            -- FASE 4: fim
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
    -- CORREÇÃO FASE 6: (C1) item 1: a chave material de cima, com inicio_mat_dito quando o dia dito dá outro início (só com
    -- a data provável em uso; sem ela, o material é o de antes, byte a byte). A última chave igual do objeto vale.
    'material', jsonb_build_object(
      'estado', v_mat_estado, 'itens', v_itens, 'dpm', v_dpm,
      'gargalo', (select e ->> 'descricao' from jsonb_array_elements(v_crit) with ordinality t(e, o)
                   where e ->> 'nivel' <> 'A' and v_dpm is not null and (e ->> 'data')::date = v_dpm order by o limit 1),
      'confianca', v_confianca, 'inicio_mat', v_inicio_mat, 'embutidas', v_embut,
      'conferido_em', p.material_conferido_em)
      || case when v_inicio_dito is not null and v_inicio_dito is distinct from v_inicio_mat
              then jsonb_build_object('inicio_mat_dito', v_inicio_dito) else '{}'::jsonb end,
    -- CORREÇÃO FASE 6: fim
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
  'Agenda de Produção (Fase 1, P3; Fase 2, P2; Fase 4, P2: a linha de OC recebida ligada a um item de texto livre da conta conta só nele, não de novo como item da OC que já chegou; Fase 4, P1: o prazo de cada item é o do fornecedor — _agenda_prazo_do_fornecedor, com o que o dono disse, o cadastro repetido, o nome e a cidade tolerante ao caractere quebrado; o importado conta em dias corridos; o item ganha prazo_texto, duvida e corridos; o texto livre é coberto pela linha da OC ligada a ele): a prontidão de uma OS em p_hoje. Estado (o 1º que valer): congelada → concluida → fora_da_carteira → em_execucao/parada → fixada/programada (Fase 2: tem meio-dia vigente de hoje em diante, fixado ou publicado) → marcada (a janela antiga; só fora de modo_proposta ligado) → sem_sinal → aguardando_cliente → esperando_voce → aguardando_material → pronta. Parada (Fase 2) = em andamento, sem evidência (diária ligada, meio-dia cumprido/parcial ou check-in) há parada_du dias úteis e sem dia no plano. Restrições {tipo, quem (dono|cliente|terceiro), texto, bloqueia, desde, compre_ate, pergunta}, a mais forte primeiro. Material efetivo = conta bruta + fato informado em os_material, níveis A (na mão, quantidade completa) / B (previsão do fornecedor, nota, OC, Pix) / C (previsão do dono) / D (sem previsão: comprado em + prazo da classe, ou "se comprar hoje") / E (sem fornecedor nem classe); "material não conferido" com zero itens ou peça embutida em aberto; dpm, início pelo material (chegada + folga_material_du, sem folga remota), est, compre até para trás, prazo efetivo (precisa_ate ou aprovação + prazo_padrao_du) e razão crítica. Saída também com plano (_agenda_plano_da_os; null sem alocação), ultima_evidencia e ultima_diaria. Também aceita OS fora da carteira. Fase 6 (P3): no item de nível B, enquanto o dia dito não chegou e com o atraso do fornecedor em uso (fornecedor_atraso: _agenda_aprendido), data = a data provável (o dia dito + o atraso; é ela que move o DPM, o início pelo material e o motor), data_dita = o dia dito (o fato) e data_texto "a OC diz qui 05/11; Kamell costuma atrasar até 2 dias úteis: conto com seg 09/11"; atrasado e sem_data continuam pelo dia dito (a "chegou?"); C, A, D e E não mudam; sem atraso em uso, o item é o de antes. CORREÇÃO FASE 6 (C1): (item 1) material.inicio_mat_dito = o início pelo material pelo dia DITO (sem o atraso do fornecedor), só quando a data provável muda o início — _agenda_violacoes julga por ele o que já está publicado; (item 2) a previsão da nota (nfe) não ganha o atraso do fornecedor (já é saída + prazo); (item 8) o atraso é lido pela chave da medida (_agenda_fornecedor_da_medida: o inativo pelo principal). Sem atraso em uso, a saída é a de antes, byte a byte. CORREÇÃO 29/10 (P5): (1) o prazo do fornecedor uma vez por item (a barreira no passo 6; antes ~25 contas por item); (2) dentro da rodada da vigia (agenda.rodada), o resultado de cada OS é lembrado (_agenda_rodada_lembrar e _agenda_rodada_guardar), enquanto a transação não grava nada no que ela lê. O resultado é o mesmo, byte a byte.';

-- agenda_vigiar (de 20261025100300_agenda_fase2_conferencia_vigia.sql)
create or replace function public.agenda_vigiar(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos      constant text[] := array['limpeza', 'sem_registro', 'violacoes', 'reservas', 'material', 'dia_nao_cumprido',
                                         'publicacao', 'conferencia', 'chegou', 'parada', 'estouro', 'duracao_material',
                                         'padrao_do_dono', 'backlog', 'poda'];
  c_da_proposta constant text[] := array['sem_registro', 'violacoes', 'reservas', 'material', 'dia_nao_cumprido', 'publicacao'];
  c_da_vigia    constant text[] := array['conferencia', 'chegou', 'parada', 'estouro', 'duracao_material', 'padrao_do_dono',
                                         'backlog'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_acordes jsonb := '[]'::jsonb;
  v_estado  text;
  v_msg     text;
  v_cota    int;
  -- CORREÇÃO 29/10 (P5): o tempo de cada passo e a memória da rodada
  v_tp      timestamptz;
  v_ms      jsonb := '{}'::jsonb;
  v_extra   jsonb;
  -- CORREÇÃO 29/10 (P5): fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da vigia.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  cf := public._agenda_cfg();
  if cf.modo_proposta = 'desligado' and cf.modo_vigia = 'desligado' then
    return jsonb_build_object('rodou', false, 'modos', jsonb_build_object('proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
                              'acordes', '[]'::jsonb);
  end if;
  -- CORREÇÃO 29/10 (P5): abre a memória da rodada (a prontidão de cada OS calculada uma vez enquanto nada do que ela lê é
  -- gravado), a não ser que agenda_config.vigia_memoria esteja desligada.
  perform public._agenda_rodada_abrir(case when coalesce(cf.vigia_memoria, true) then p_hoje end);
  -- CORREÇÃO 29/10 (P5): fim

  foreach v_passo in array c_passos loop
    continue when v_passo = any (c_da_proposta) and cf.modo_proposta = 'desligado';
    continue when v_passo = any (c_da_vigia) and cf.modo_vigia = 'desligado';
    -- CORREÇÃO 29/10 (P5): o tempo do passo
    v_tp := clock_timestamp();
    -- CORREÇÃO 29/10 (P5): fim
    begin
      execute format('select public.%I($1, $2)', '_agenda_vigia_' || v_passo) into v_r using p_hoje, p_agora;
      v_acordes := v_acordes || coalesce(v_r -> 'acordes', '[]'::jsonb);
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb) - 'acordes');
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('vigia da agenda, passo %s: %s', v_passo, v_msg), 'agenda', 'vigia:' || v_passo,
                                   'error', jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                               'p_agora', p_agora));
    end;
    -- CORREÇÃO 29/10 (P5): o tempo do passo (ms), para medir em produção qual passo pesa
    v_ms := v_ms || jsonb_build_object(v_passo, greatest(0, (extract(epoch from clock_timestamp() - v_tp) * 1000)::int));
    -- CORREÇÃO 29/10 (P5): fim
  end loop;

  -- Os acordes: só com a vigia ligada e a ação executada; no máximo acordes_dia_max por dia; a perda mais cedo primeiro.
  if cf.modo_vigia = 'ligado' and jsonb_array_length(v_acordes) > 0 then
    v_cota := greatest(cf.acordes_dia_max - (select count(*)::int from public.agenda_acoes a
                                              where a.dia = p_hoje and a.contada_via = 'acorde'), 0);
    select coalesce(jsonb_agg(q.e order by q.ord), '[]'::jsonb) into v_acordes
      from (select e, row_number() over (order by (e ->> 'perda_em')::date nulls last, e ->> 'chave') as ord
              from jsonb_array_elements(v_acordes) e
             where exists (select 1 from public.agenda_acoes a where a.id = (e ->> 'acao_id')::uuid and a.executada)) q
     where q.ord <= v_cota;
  else
    v_acordes := '[]'::jsonb;
  end if;
  -- CORREÇÃO 29/10 (P5): fecha a memória (nada dela sobra para o resto da transação) e guarda na linha da rodada o tempo de
  -- cada passo (ms) e quantas contas a memória fez e poupou (memoria); o que a vigia devolve não muda.
  v_extra := jsonb_build_object('ms', v_ms, 'memoria', public._agenda_rodada_fechar());
  v_cont := v_cont || v_extra;
  -- CORREÇÃO 29/10 (P5): fim

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('acordes', jsonb_array_length(v_acordes), 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int));
  -- CORREÇÃO 29/10 (P5): o tempo e a memória ficam só na linha da rodada
  v_cont := v_cont - 'ms' - 'memoria';
  -- CORREÇÃO 29/10 (P5): fim

  return jsonb_build_object('rodou', true, 'modos', jsonb_build_object('proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
                            'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas, 'acordes', v_acordes);
end;
$function$;

comment on function public.agenda_vigiar(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a vigia de 15 min (chamada pelo task-automations). Os dois modos desligados = {rodou: false}. Passos, cada um no seu bloco (o que falha vai para app_error_logs, context agenda, action vigia:<passo>, e os outros rodam): 1 limpeza; 2 sem registro; 3 violações → replano e acorde; 4 reservas (promove/solta); 5 material completo (porta/encaixe); 6 dia não cumprido; 7 publicação da semana (dia_do_plano, hora_do_plano, uma vez); 8 conferência; 9 chegou?; 10 parada? (substitui a R2); 11 estouro; 12 duração/material; 13 dono sem padrão; 14 pouco serviço na fila; 15 poda. 2 a 7 seguem modo_proposta; 8 a 14, modo_vigia. Uma linha em agenda_vigia_rodadas por tique. {rodou, modos, contagens, erros, falhas, acordes:[{chave agenda:<acao>, assunto os:<os>, texto, acao_id, os, perda_em}]} — acorde só com a vigia ligada e a ação executada, até acordes_dia_max por dia. Só service_role. CORREÇÃO 29/10 (P5): a rodada abre a memória (a prontidão de cada OS calculada uma vez enquanto nada do que ela lê é gravado; agenda_config.vigia_memoria = false desliga) e a linha de agenda_vigia_rodadas guarda contagens.ms (o tempo de cada passo) e contagens.memoria (quantas prontidões a memória calculou e quantas poupou). O que a vigia devolve não muda.';

-- ── 4. As portas ─────────────────────────────────────────────────────────────────────────────────────────────
-- As peças da memória são só de dentro da vigia (que roda como dona, security definer): ninguém de fora as chama, nem o
-- service_role. Fora da rodada, os_prontidao nem chega a chamá-las; com agenda.rodada posta à mão por um login, a
-- prontidão dele recusa (42501) em vez de ler ou escrever na memória. As 2 recriadas mantêm as portas que tinham (create or
-- replace não mexe no grant).
revoke all on function public._agenda_rodada_marca() from public, anon, authenticated, service_role;
revoke all on function public._agenda_rodada_contar(text) from public, anon, authenticated, service_role;
revoke all on function public._agenda_rodada_abrir(date) from public, anon, authenticated, service_role;
revoke all on function public._agenda_rodada_fechar() from public, anon, authenticated, service_role;
revoke all on function public._agenda_rodada_lembrar(uuid) from public, anon, authenticated, service_role;
revoke all on function public._agenda_rodada_guardar(uuid, bigint, jsonb) from public, anon, authenticated, service_role;
