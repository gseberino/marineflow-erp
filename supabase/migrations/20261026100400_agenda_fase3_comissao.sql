-- Agenda de Produção, Fase 3 ("A execução: equipe, diária, conclusão e telas"), pacote P5: a comissão "o maior dos
-- dois" — SÓ A CONTA. Calcula e resume, por mês e por técnico; não paga nada e não cria conta a pagar, lançamento nem
-- recebível.
-- Spec: scratchpad agenda-pesquisa/spec-fase3.md (§8, §13.3, §13.5, §19 item 2). Decisões do dono 23/10 (Comissão).
-- Depende de 20261026100000 (comissao_config) e da Fase 1 (agenda_somar_du, _agenda_nome_curto, _agenda_lista).
--
-- ═══ DDL — OK NOMEADO ═══ (1 view nova; 2 funções novas, só de leitura; 1 coluna nova e 1 CHECK ampliado em
-- comissao_config, ambos com o DEFAULT de hoje)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: o dono pediu ajuda para decidir a comissão e escolheu, por 3 meses, "o maior dos dois": a diária continua
-- sendo o piso; todo mês, pct (20%) do lucro líquido de cada OS concluída E recebida, dividido entre os técnicos pelos
-- dias trabalhados nela; se a comissão passar das diárias, a diferença seria bônus. Lucro líquido = recebido − material ao
-- custo − despesas da OS − imposto da nota − taxa do cartão; as diárias NÃO são descontadas. A regra de PAGAMENTO depende
-- do "pode pagar assim" do dono, que ainda não veio: aqui só a conta e o resumo "diárias R$ X × comissão R$ Y".
--
-- O QUE MUDA:
--   1. v_dias_por_os_e_pessoa (security_invoker): os dias de cada pessoa em cada OS, pelas diárias ligadas a ela
--      (work_shift_os), com a mesma divisão de v_custo_real_mao_de_obra_por_os (o turno com n OS vale fracao/n em cada
--      uma). Só perfil de diária; o sócio nunca entra. Não filtra status, como a conta corrente (NOVO-agenda-18: a view
--      antiga não agrupa por pessoa).
--   2. comissao_config: competencia ('concluida_e_paga' | 'saida', nasce 'concluida_e_paga') e imposto_fonte ganha
--      'aliquota_simples_sempre'. As duas premissas que o dono ainda confirma viram parâmetro, trocáveis sem migration.
--   3. comissao_tecnicos_do_mes(p_mes, p_hoje): a conta do mês (OS a OS, a divisão, cada técnico, o que ficou sem dia
--      para dividir, o que espera pagamento, os avisos) e o texto da conversa.
--   4. comissao_resumo_do_mes(p_mes, p_hoje): {mes, ate, primeiro_dia_util, texto, linha}. Sem p_mes, o mês corrente;
--      até o 1º dia útil do mês (inclusive), o mês anterior. A linha (≤ 200 caracteres) é a do fechamento do 1º dia útil
--      (o P6 a põe em _agenda_linhas_do_fechamento).
--
-- O QUE NÃO MUDA: nada é escrito. As duas funções são STABLE (o Postgres recusa INSERT/UPDATE/DELETE dentro delas) e não
-- tocam commissions, payables, payments, receivables nem work_shifts; não chamam registrar_diaria; não mandam nada a
-- ninguém. O texto diz sempre "nada foi pago" e nunca "a pagar" nem "vou pagar": diz "seria". comissao_config.pagamento
-- continua só 'desligado' (CHECK de 20261026100000). Nenhum cron, nenhuma tela, nenhuma função de borda.
--
-- PREMISSAS QUE O DONO AINDA CONFIRMA (spec §19 item 2), cada uma num lugar só:
--   (a) imposto = alíquota do Simples (company_fiscal_settings.nfse_total_tax_rate_sn, senão a linha simples_aliquota de
--       app_settings; hoje 6%) × o recebido, só nas OS com nota autorizada de produção → comissao_config.imposto_fonte
--       ('aliquota_simples_com_nota' | 'aliquota_simples_sempre' | 'nenhum');
--   (b) a OS entra no mês em que ficou concluída E paga (o mais tarde dos dois) → comissao_config.competencia
--       ('concluida_e_paga' | 'saida' = o mês da conclusão, quando já paga);
--   (c) OS sem diária ligada fica "sem dia para dividir" (nao_atribuida) → o comentário "PREMISSA (c)" no corpo;
--   (d) quando começam os 3 meses de teste → comissao_config.inicio (nulo = o dono ainda não disse; o texto pede);
--   (e) o "pode pagar assim" → outra fase, numa migration que troque o CHECK de comissao_config.pagamento.
--
-- O QUE A CONTA NÃO SABE HOJE (o texto diz):
--   · 0 das 56 diárias de produção estão ligadas a uma OS (work_shift_os vazia): toda a comissão fica "sem dia lançado
--     na OS para dividir" — o resumo mostra o valor e quantas diárias do mês estão sem OS;
--   · as despesas da OS não são lançadas (só a OS-00105 tem, R$ 1.905): o lucro sai maior do que o real;
--   · só a OS-00060 e a OS-00075 têm nota emitida: nas outras, o imposto fica de fora (premissa a).
--   Medido em produção (SELECT de 24/10, sql/i04, i09): de 07/09 a 17/10 as diárias somam R$ 6.040,00 (setembro
--   R$ 3.220,00 + outubro até 17/10 R$ 2.820,00); pela regra, setembro dá R$ 226,00 (OS-00105) e outubro R$ 2.094,20
--   (OS-00094/61/77/110), tudo sem dia para dividir. O "≈ R$ 6.600" das decisões de 23/10 era 20% do VALOR das 6 OS
--   concluídas no período, pagas ou não (R$ 6.614,22, dos quais R$ 3.378,00 da OS-00038, que não foi paga): a regra só
--   conta o que entrou. Os dois números estão provados no espelho (supabase/tests/agenda_fase3_comissao.sql, P).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase3_comissao.sql):
--   · A alíquota de reserva é a LINHA app_settings.key = 'simples_aliquota' (a que a tela Configurações › Fiscal grava e
--     o produto lê), não a coluna simples_aliquota: app_settings é chave/valor e a coluna é um DEFAULT 6 repetido em
--     toda linha, que a tela nunca muda.
--   · Nota que conta: autorizada E de produção (environment = 'producao'). Uma nota de homologação não é imposto.
--   · "Sem p_mes, o mês anterior quando p_hoje é o 1º dia útil": vale também ANTES dele (dom 01 e seg 02/11, Finados,
--     ainda mostram outubro). Senão, nesses dois dias, "comissão" mostraria um novembro vazio.
--   · O texto lista os técnicos com diária ou comissão no mês (o exemplo da spec só tinha o Roberto, mas o João tem
--     diárias em outubro); quem tem zero nos dois fica só no JSON. A espera do pagamento lista TODAS as OS concluídas no
--     mês e ainda não pagas (em outubro, a OS-00038 e também a OS-00051, paga em parte).
--   · O aviso sem_nota só sai com imposto_fonte = 'aliquota_simples_com_nota' (nos outros a nota não muda a conta); a OS
--     continua com sem_nota no JSON.
--   · Avisos novos: aguardando_pagamento, lucro_negativo, sem_aliquota e mes_futuro.
--
-- RISCO REGISTRADO: payment_status é mantido por gatilho e lido como está hoje. A OS paga e depois estornada sai da conta
-- do mês em que tinha entrado; o mês passado pode mudar quando um pagamento atrasado chega (com competencia = 'saida').
--
-- ORDEM DE LIGAR: depois de 20261026100000 (comissao_config); independe das outras da Fase 3. Aplicar sozinha não muda
-- nada para ninguém: só o P6 passa a ler (agenda_ver foco comissao e a linha do 1º dia útil no fechamento).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase3_comissao.sql (begin/rollback; sem os cenários da bancada só as
-- portas rodam). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261026100400
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261026100400_agenda_fase3_comissao.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261026100400', 'agenda_fase3_comissao');"
--
-- IDEMPOTENTE: add column if not exists (com o CHECK junto), CHECK ampliado por drop if exists + add com o mesmo nome,
-- create or replace view/function, revoke/grant de novo.

-- ── 1. As premissas como parâmetro ──────────────────────────────────────────────────────────────────────
alter table public.comissao_config
  add column if not exists competencia text not null default 'concluida_e_paga'
    constraint comissao_config_competencia_check check (competencia in ('concluida_e_paga', 'saida'));

alter table public.comissao_config drop constraint if exists comissao_config_imposto_fonte_check;
alter table public.comissao_config add constraint comissao_config_imposto_fonte_check
  check (imposto_fonte in ('aliquota_simples_com_nota', 'aliquota_simples_sempre', 'nenhum'));

comment on column public.comissao_config.competencia is
  'Premissa (b), a confirmar pelo dono: concluida_e_paga = a OS entra no mês em que ficou concluída E paga (o mais tarde dos dois: a saída em Brasília ou o último pagamento confirmado); saida = no mês da conclusão, depois de paga (o mês passado pode mudar quando o pagamento chega).';
comment on column public.comissao_config.imposto_fonte is
  'Premissa (a), a confirmar pelo dono: aliquota_simples_com_nota = a alíquota do Simples (company_fiscal_settings.nfse_total_tax_rate_sn, senão a linha simples_aliquota de app_settings) × o recebido, só com nota autorizada de produção ligada à OS; aliquota_simples_sempre = a mesma alíquota em toda OS; nenhum = sem imposto na conta.';

-- ── 2. Os dias de cada pessoa em cada OS ────────────────────────────────────────────────────────────────
create or replace view public.v_dias_por_os_e_pessoa with (security_invoker = on) as
with partes as (
  select wo.service_order_id, wp.payee_id, ws.id as shift_id, ws.data, ws.fracao, ws.valor_dia,
         count(*) over (partition by ws.id) as n_os
    from public.work_shift_os wo
    join public.work_shifts ws on ws.id = wo.shift_id
    join public.work_profiles wp on wp.id = ws.work_profile_id
    join public.payees p on p.id = wp.payee_id
   where ws.fracao is not null
     and wp.modo_pagamento = 'diaria'
     and p.kind is distinct from 'socio'
)
select service_order_id,
       payee_id,
       sum(fracao / n_os)                  as dias,
       round(sum(valor_dia / n_os), 2)     as valor,
       min(data)                           as primeiro_dia,
       max(data)                           as ultimo_dia
  from partes
 group by service_order_id, payee_id;

comment on view public.v_dias_por_os_e_pessoa is
  'Agenda de Produção (Fase 3, P5): os dias de cada pessoa em cada OS — as diárias (fracao não nula) ligadas à OS em work_shift_os, o turno com n OS valendo fracao/n em cada uma (a divisão de v_custo_real_mao_de_obra_por_os, que não agrupa por pessoa). Só perfil de diária; o sócio nunca entra. Não filtra status. dias sem arredondar (é a base da divisão da comissão); valor em centavos.';

revoke all on table public.v_dias_por_os_e_pessoa from public, anon, authenticated;
grant select on table public.v_dias_por_os_e_pessoa to authenticated, service_role;

-- ── 3. A conta do mês ───────────────────────────────────────────────────────────────────────────────────
create or replace function public.comissao_tecnicos_do_mes(p_mes date, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cfg          public.comissao_config;
  v_uid        uuid := auth.uid();
  v_papel      text;
  v_meses      constant text[] := array['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto',
                                        'setembro', 'outubro', 'novembro', 'dezembro'];
  v_de         date;
  v_fim        date;
  v_ate        date;
  v_nome_mes   text;
  v_aliq       numeric;
  v_aliq_txt   text;
  v_pct_txt    text;
  v_em_teste   boolean;
  v_mes_teste  int;
  v_os         jsonb;
  v_partes     jsonb;
  v_tec        jsonb;
  v_aguarda    jsonb;
  v_nao        numeric;
  v_nao_os     jsonb;
  v_n_os       int;
  v_desp       numeric;
  v_sem_nota   int;
  v_negativas  text[];
  v_n_diarias  int;
  v_sem_os     int;
  v_avisos     text[] := array['pagamento_desligado'];
  v_linhas     text[] := '{}';
  v_conta      text[] := '{}';
  v_cab        text;
  v_premissas  text[];
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (o assistente, o fechamento). Um JWT de outro
  -- papel sem "sub" não ganha a conta.
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'A comissão é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'A comissão é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;

  if p_mes is null or p_hoje is null then
    raise exception 'comissao_tecnicos_do_mes: diga o mês e o dia de hoje.' using errcode = '22004';
  end if;
  select * into cfg from public.comissao_config c where c.id;
  if not found then
    raise exception 'comissao_config sem a linha: parâmetro nunca é inventado.' using errcode = 'P0002';
  end if;

  v_de := make_date(extract(year from p_mes)::int, extract(month from p_mes)::int, 1);
  v_fim := (v_de + interval '1 month')::date - 1;
  v_ate := least(v_fim, p_hoje);
  v_nome_mes := v_meses[extract(month from v_de)::int];
  v_pct_txt := replace(trim_scale(cfg.pct * 100)::text, '.', ',') || '%';

  -- O teste de 3 meses (premissa d): fora dele (ou sem início dito) a conta é "em teste".
  v_mes_teste := case when cfg.inicio is null then null
                      else (extract(year from v_de)::int - extract(year from cfg.inicio)::int) * 12
                           + extract(month from v_de)::int - extract(month from cfg.inicio)::int + 1 end;
  v_em_teste := v_mes_teste is null or v_mes_teste < 1 or v_mes_teste > cfg.meses_teste;
  if v_em_teste then v_avisos := v_avisos || 'teste'::text; end if;

  if v_ate < v_de then
    return jsonb_build_object(
      'mes', v_de, 'ate', null, 'nome_mes', v_nome_mes, 'pct', cfg.pct, 'competencia', cfg.competencia,
      'imposto_fonte', cfg.imposto_fonte, 'aliquota', null,
      'teste', jsonb_build_object('em_teste', v_em_teste, 'inicio', cfg.inicio, 'meses', cfg.meses_teste, 'mes_do_teste', v_mes_teste),
      'tecnicos', '[]'::jsonb, 'os', '[]'::jsonb, 'aguardando_pagamento', '[]'::jsonb,
      'nao_atribuida', 0, 'nao_atribuida_os', '[]'::jsonb, 'diarias_do_mes', jsonb_build_object('diarias', 0, 'sem_os', 0),
      'avisos', to_jsonb(v_avisos || 'mes_futuro'::text),
      'texto', format('Comissão de %s: o mês ainda não começou. Nada foi pago.', v_nome_mes));
  end if;

  -- Premissa (a): a alíquota do Simples. A nota emitida não guarda o valor do imposto: ele é calculado.
  v_aliq := coalesce(
    (select f.nfse_total_tax_rate_sn from public.company_fiscal_settings f order by f.created_at, f.id limit 1),
    (select replace(btrim(s.value), ',', '.')::numeric from public.app_settings s
      where s.key = 'simples_aliquota' and btrim(s.value) ~ '^[0-9]+([.,][0-9]+)?$'));
  v_aliq_txt := replace(trim_scale(coalesce(v_aliq, 0))::text, '.', ',') || '%';

  -- ── As OS do mês, uma a uma ──
  with pg as (
    -- o que entrou: pagamentos confirmados dos recebíveis vivos da OS (o sinal entra)
    select r.service_order_id as os_id,
           sum(p.amount) as recebido,
           sum(case when p.net_amount is not null then p.amount - p.net_amount
                    else p.amount * coalesce(p.card_fee_percent, 0) / 100 end) as taxa,
           max(p.payment_date) as ultimo
      from public.receivables r
      join public.payments p on p.receivable_id = r.id
     where r.service_order_id is not null and r.status is distinct from 'cancelled' and p.status = 'confirmed'
     group by r.service_order_id
  ), concluidas as (
    select so.id, so.service_order_number as numero, so.payment_status,
           (so.check_out_at at time zone 'America/Sao_Paulo')::date as saida,
           coalesce(pg.recebido, 0) as recebido, coalesce(pg.taxa, 0) as taxa, pg.ultimo
      from public.service_orders so
      left join pg on pg.os_id = so.id
     where so.status in ('completed', 'invoiced') and so.check_out_at is not null
  ), pagas as (
    -- PREMISSA (b): concluída E paga; o mês é o do mais tarde dos dois (ou o da saída, com competencia = 'saida').
    select c.*, case cfg.competencia when 'saida' then c.saida else greatest(c.saida, c.ultimo) end as competencia
      from concluidas c
     where c.payment_status = 'paid' and greatest(c.saida, c.ultimo) <= p_hoje
  ), do_mes as (
    select d.*,
           round(coalesce((select sum(coalesce(sp.line_total_cost, sp.quantity * sp.unit_cost_snapshot))
                             from public.service_order_parts sp where sp.service_order_id = d.id), 0), 2) as material,
           -- faturáveis ou não: a faturável entrou no recebido como repasse e sai aqui
           round(coalesce((select sum(e.amount) from public.service_order_expenses e where e.service_order_id = d.id), 0), 2)
             as despesas,
           exists (select 1 from public.issued_fiscal_documents f
                    where f.origin_type = 'service_order' and f.origin_id = d.id
                      and f.status = 'authorized' and f.environment = 'producao') as tem_nota
      from pagas d
     where d.competencia between v_de and v_ate
  ), com_imposto as (
    select o.*, round(o.recebido, 2) as recebido2, round(o.taxa, 2) as taxa2,
           case when cfg.imposto_fonte = 'aliquota_simples_sempre'
                  or (cfg.imposto_fonte = 'aliquota_simples_com_nota' and o.tem_nota)
                then round(o.recebido * coalesce(v_aliq, 0) / 100, 2) else 0 end as imposto
      from do_mes o
  ), lucro as (
    -- as diárias NÃO são descontadas (decisão do dono)
    select c.*, c.recebido2 - c.material - c.despesas - c.imposto - c.taxa2 as lucro from com_imposto c
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id, 'numero', l.numero, 'saida', l.saida, 'competencia', l.competencia,
           'recebido', l.recebido2, 'material', l.material, 'despesas', l.despesas, 'imposto', l.imposto,
           'taxa_cartao', l.taxa2, 'lucro', l.lucro, 'comissao', round(cfg.pct * greatest(l.lucro, 0), 2),
           'sem_nota', not l.tem_nota, 'lucro_negativo', l.lucro < 0)
           order by l.competencia, l.numero, l.id), '[]'::jsonb)
    into v_os
    from lucro l;

  -- ── A divisão pelos dias de cada um ──
  -- A sobra dos centavos vai à maior parte; no empate, ao menor payee_id.
  -- PREMISSA (c): OS sem dia ligado não entra aqui e fica inteira em nao_atribuida ("sem dia para dividir").
  with os as (
    select * from jsonb_to_recordset(v_os) as x(id uuid, numero text, competencia date, comissao numeric)
  ), dias as (
    select v.service_order_id as os_id, v.payee_id, v.dias
      from public.v_dias_por_os_e_pessoa v
     where v.service_order_id in (select id from os) and v.dias > 0
  ), base as (
    select d.os_id, d.payee_id, d.dias, o.numero, o.competencia, o.comissao,
           sum(d.dias) over (partition by d.os_id) as dias_total,
           round(o.comissao * d.dias / sum(d.dias) over (partition by d.os_id), 2) as parte0,
           row_number() over (partition by d.os_id order by d.dias desc, d.payee_id) as ordem
      from dias d join os o on o.id = d.os_id
  ), partes as (
    select b.*, b.parte0 + case when b.ordem = 1 then b.comissao - sum(b.parte0) over (partition by b.os_id) else 0 end
                  as parte
      from base b
  )
  select coalesce(jsonb_agg(jsonb_build_object('os_id', p.os_id, 'numero', p.numero, 'competencia', p.competencia,
                                               'payee_id', p.payee_id, 'dias', p.dias, 'dias_total', p.dias_total,
                                               'parte', p.parte)
                            order by p.competencia, p.numero, p.os_id, p.ordem), '[]'::jsonb)
    into v_partes
    from partes p;

  -- o total de dias em cada OS (0 = sem dia ligado)
  select coalesce(jsonb_agg(e || jsonb_build_object('dias_total',
           coalesce((select round(sum((p ->> 'dias')::numeric), 2) from jsonb_array_elements(v_partes) p
                      where p ->> 'os_id' = e ->> 'id'), 0)) order by n), '[]'::jsonb)
    into v_os
    from jsonb_array_elements(v_os) with ordinality as x(e, n);

  -- ── Cada técnico: diárias do mês × a soma das partes ──
  with partes as (
    select * from jsonb_to_recordset(v_partes)
             as x(os_id uuid, numero text, competencia date, payee_id uuid, dias numeric, parte numeric)
  ), pessoas as (
    select p.id, p.name
      from public.payees p
     where p.kind is distinct from 'socio'
       and (exists (select 1 from public.work_profiles wp
                     where wp.payee_id = p.id and wp.modo_pagamento = 'diaria'
                       and wp.vigencia_inicio <= v_ate and (wp.vigencia_fim is null or wp.vigencia_fim >= v_de))
            or exists (select 1 from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
                        where wp.payee_id = p.id and ws.fracao is not null and ws.data between v_de and v_ate)
            or p.id in (select pa.payee_id from partes pa))
  ), turnos as (
    -- a mesma soma da conta corrente: valor_dia das diárias (fracao não nula) com data no mês
    select wp.payee_id, ws.valor_dia, ws.fracao,
           exists (select 1 from public.work_shift_os wo where wo.shift_id = ws.id) as tem_os
      from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
     where ws.fracao is not null and ws.data between v_de and v_ate
  ), t as (
    select pe.id as payee_id, public._agenda_nome_curto(pe.name) as nome,
           round(coalesce((select sum(tu.valor_dia) from turnos tu where tu.payee_id = pe.id), 0), 2) as diarias,
           (select count(*) from turnos tu where tu.payee_id = pe.id and tu.fracao > 0)::int as n_diarias,
           (select count(*) from turnos tu where tu.payee_id = pe.id and tu.fracao > 0 and not tu.tem_os)::int as sem_os,
           coalesce((select sum(pa.parte) from partes pa where pa.payee_id = pe.id), 0) as comissao,
           coalesce((select jsonb_agg(jsonb_build_object('numero', pa.numero, 'parte', pa.parte, 'dias', round(pa.dias, 2))
                                      order by pa.competencia, pa.numero, pa.os_id)
                       from partes pa where pa.payee_id = pe.id), '[]'::jsonb) as os
      from pessoas pe
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'payee_id', t.payee_id, 'nome', t.nome, 'diarias', t.diarias, 'n_diarias', t.n_diarias, 'diarias_sem_os', t.sem_os,
           'comissao', t.comissao, 'maior', greatest(t.diarias, t.comissao), 'bonus', greatest(t.comissao - t.diarias, 0),
           'os', t.os)
           order by greatest(t.diarias, t.comissao) desc, t.nome, t.payee_id), '[]'::jsonb),
         coalesce(sum(t.n_diarias), 0), coalesce(sum(t.sem_os), 0)
    into v_tec, v_n_diarias, v_sem_os
    from t;

  -- ── O que não deu para dividir e o que espera pagamento ──
  select coalesce(sum(o.comissao), 0),
         coalesce(jsonb_agg(jsonb_build_object('numero', o.numero, 'comissao', o.comissao)
                            order by o.competencia, o.numero, o.id) filter (where o.comissao > 0), '[]'::jsonb)
    into v_nao, v_nao_os
    from jsonb_to_recordset(v_os) as o(id uuid, numero text, competencia date, comissao numeric, dias_total numeric)
   where o.dias_total = 0;

  select coalesce(jsonb_agg(jsonb_build_object('numero', so.service_order_number, 'saida', s.saida, 'pagamento', so.payment_status)
                            order by s.saida, so.service_order_number, so.id), '[]'::jsonb)
    into v_aguarda
    from public.service_orders so
    cross join lateral (select (so.check_out_at at time zone 'America/Sao_Paulo')::date as saida) s
   where so.status in ('completed', 'invoiced') and so.check_out_at is not null
     and s.saida between v_de and v_ate and so.payment_status is distinct from 'paid';

  select count(*)::int, coalesce(sum((e ->> 'despesas')::numeric), 0),
         (count(*) filter (where (e ->> 'sem_nota')::boolean))::int,
         coalesce(array_agg(e ->> 'numero' order by n) filter (where (e ->> 'lucro_negativo')::boolean), '{}')
    into v_n_os, v_desp, v_sem_nota, v_negativas
    from jsonb_array_elements(v_os) with ordinality as x(e, n);

  if v_n_os > 0 and v_desp = 0 then v_avisos := v_avisos || 'despesas_zeradas'::text; end if;
  if v_nao > 0 then v_avisos := v_avisos || 'sem_dias'::text; end if;
  if cfg.imposto_fonte = 'aliquota_simples_com_nota' and v_sem_nota > 0 then v_avisos := v_avisos || 'sem_nota'::text; end if;
  if cfg.imposto_fonte <> 'nenhum' and v_aliq is null then v_avisos := v_avisos || 'sem_aliquota'::text; end if;
  if cardinality(v_negativas) > 0 then v_avisos := v_avisos || 'lucro_negativo'::text; end if;
  if jsonb_array_length(v_aguarda) > 0 then v_avisos := v_avisos || 'aguardando_pagamento'::text; end if;

  -- ── O texto (conversa) ──
  v_cab := 'Comissão de ' || v_nome_mes
        || case when v_ate < v_fim then ' (até ' || to_char(v_ate, 'DD/MM') || ')' else '' end
        || ', ' || case when v_em_teste then 'em teste' else format('mês %s de %s do teste', v_mes_teste, cfg.meses_teste) end
        || ' — nada foi pago.';

  select coalesce(array_agg(format('• %s: diárias %s × comissão %s → %s.', e ->> 'nome',
                                   public._brl((e ->> 'diarias')::numeric), public._brl((e ->> 'comissao')::numeric),
                                   case when (e ->> 'comissao')::numeric > (e ->> 'diarias')::numeric
                                        then 'seria ' || public._brl((e ->> 'bonus')::numeric) || ' de bônus'
                                        else 'fica a diária' end) order by n), '{}')
    into v_linhas
    from jsonb_array_elements(v_tec) with ordinality as x(e, n)
   where (e ->> 'diarias')::numeric > 0 or (e ->> 'comissao')::numeric > 0;
  if v_n_os = 0 then v_linhas := v_linhas || '• Nenhuma OS concluída e paga no mês.'::text; end if;
  if v_nao > 0 then
    -- " · " entre as OS (a vírgula já está nos centavos); passou de 6, "· e mais N"
    v_linhas := v_linhas || format('• Sem dia lançado na OS para dividir: %s (%s%s).', public._brl(v_nao),
      array_to_string(array(select (e ->> 'numero') || ' ' || public._brl((e ->> 'comissao')::numeric)
                              from jsonb_array_elements(v_nao_os) with ordinality as x(e, n) where n <= 6 order by n), ' · '),
      case when jsonb_array_length(v_nao_os) > 6 then format(' · e mais %s', jsonb_array_length(v_nao_os) - 6) else '' end);
  end if;

  v_conta := v_conta || format('A conta: %s do que entrou menos o material ao custo, as despesas da OS%s e a taxa do cartão; as diárias não entram.',
    v_pct_txt, case cfg.imposto_fonte when 'nenhum' then '' when 'aliquota_simples_sempre' then ', o imposto do Simples'
                                       else ', o imposto da nota' end);
  if v_sem_os > 0 then
    v_conta := v_conta || case when v_sem_os = v_n_diarias
      then format('Nenhuma das %s diárias do mês está ligada a uma OS: elas não contam na divisão.', v_n_diarias)
      else format('%s das %s diárias do mês não estão ligadas a uma OS: elas não contam na divisão.', v_sem_os, v_n_diarias) end;
  end if;
  if 'despesas_zeradas' = any (v_avisos) then
    v_conta := v_conta || 'As despesas das OS não estão lançadas (R$ 0 em todas), então o lucro está maior do que o real.'::text;
  end if;
  if 'sem_nota' = any (v_avisos) then
    v_conta := v_conta || format('O imposto (%s do Simples) só entra nas OS com nota emitida: %s.', v_aliq_txt,
      case when v_sem_nota < v_n_os then format('%s das %s estão sem nota', v_sem_nota, v_n_os)
           when v_n_os = 1 then 'a OS está sem nota' else format('as %s estão sem nota', v_n_os) end);
  end if;
  if 'sem_aliquota' = any (v_avisos) then
    v_conta := v_conta || 'A alíquota do Simples não está nas configurações fiscais: o imposto ficou em R$ 0.'::text;
  end if;
  if cardinality(v_negativas) > 0 then
    v_conta := v_conta || format('Sem lucro na conta, comissão zero: %s.', public._agenda_lista(v_negativas, 4));
  end if;
  if jsonb_array_length(v_aguarda) > 0 then
    v_conta := v_conta || format('%s: %s.',
      case when jsonb_array_length(v_aguarda) = 1 then 'Entra quando for paga' else 'Entram quando forem pagas' end,
      public._agenda_lista(array(select e ->> 'numero' from jsonb_array_elements(v_aguarda) with ordinality as x(e, n)
                                  order by n), 4));
  end if;
  if cfg.inicio is null then
    v_premissas := array[
      case cfg.imposto_fonte when 'aliquota_simples_com_nota' then 'se o imposto é só nas OS com nota'
                             when 'aliquota_simples_sempre' then 'se o imposto entra em toda OS'
                             else 'se a conta fica sem imposto' end,
      case cfg.competencia when 'saida' then 'se a OS conta no mês da conclusão, depois de paga'
                           else 'se a OS conta no mês em que ficou concluída e paga' end,
      format('quando começam os %s meses de teste', cfg.meses_teste)];
    v_conta := v_conta || ('Para a conta valer, falta você dizer ' || public._agenda_lista(v_premissas) || '.');
  end if;

  return jsonb_build_object(
    'mes', v_de, 'ate', v_ate, 'nome_mes', v_nome_mes, 'pct', cfg.pct, 'competencia', cfg.competencia,
    'imposto_fonte', cfg.imposto_fonte, 'aliquota', v_aliq,
    'teste', jsonb_build_object('em_teste', v_em_teste, 'inicio', cfg.inicio, 'meses', cfg.meses_teste, 'mes_do_teste', v_mes_teste),
    'tecnicos', v_tec,
    'os', (select coalesce(jsonb_agg(e - 'id' order by n), '[]'::jsonb) from jsonb_array_elements(v_os) with ordinality as x(e, n)),
    'aguardando_pagamento', v_aguarda,
    'nao_atribuida', v_nao, 'nao_atribuida_os', v_nao_os,
    'diarias_do_mes', jsonb_build_object('diarias', v_n_diarias, 'sem_os', v_sem_os),
    'avisos', to_jsonb(v_avisos),
    'texto', array_to_string(array[v_cab] || v_linhas || array[array_to_string(v_conta, ' ')], E'\n'));
end;
$function$;

comment on function public.comissao_tecnicos_do_mes(date, date) is
  'Agenda de Produção (Fase 3, P5): a comissão "o maior dos dois" do mês de p_mes, até p_hoje — SÓ A CONTA, nada é pago nem gravado (STABLE). OS do mês: concluída/faturada, paga (payment_status), no mês da competência (comissao_config.competencia). Por OS: recebido (pagamentos confirmados dos recebíveis vivos), material ao custo, despesas, imposto (comissao_config.imposto_fonte × a alíquota do Simples), taxa do cartão, lucro (sem descontar diárias) e comissão = pct × lucro positivo. Divisão pelos dias de v_dias_por_os_e_pessoa (sobra de centavos à maior parte; empate, menor payee_id); OS sem dia = nao_atribuida. Por técnico: diárias do mês × comissão, o maior e o bônus que seria. Devolve {mes, ate, nome_mes, pct, competencia, imposto_fonte, aliquota, teste, tecnicos, os, aguardando_pagamento, nao_atribuida, nao_atribuida_os, diarias_do_mes, avisos, texto}. Admin/financeiro ou service_role; senão 42501.';

revoke all on function public.comissao_tecnicos_do_mes(date, date) from public, anon;
grant execute on function public.comissao_tecnicos_do_mes(date, date) to authenticated, service_role;

-- ── 4. O resumo (conversa e a linha do fechamento do 1º dia útil) ────────────────────────────────────────
create or replace function public.comissao_resumo_do_mes(p_mes date default null, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_pdu     date;
  v_mes     date;
  r         jsonb;
  v_rot     text;
  v_mes_txt text;
  v_fim     text;
  v_nao     text := '';
  v_tec     jsonb;
  v_n       int;
  v_linha   text;
begin
  if p_hoje is null then
    raise exception 'comissao_resumo_do_mes: diga o dia de hoje.' using errcode = '22004';
  end if;
  v_pdu := public.agenda_somar_du(make_date(extract(year from p_hoje)::int, extract(month from p_hoje)::int, 1), 0);
  v_mes := case
    when p_mes is not null then make_date(extract(year from p_mes)::int, extract(month from p_mes)::int, 1)
    when p_hoje <= v_pdu then (make_date(extract(year from p_hoje)::int, extract(month from p_hoje)::int, 1) - interval '1 month')::date
    else make_date(extract(year from p_hoje)::int, extract(month from p_hoje)::int, 1) end;

  -- quem vê é conferido lá dentro (admin/financeiro ou service_role)
  r := public.comissao_tecnicos_do_mes(v_mes, p_hoje);
  v_mes_txt := r ->> 'nome_mes';

  if r -> 'ate' = 'null'::jsonb then
    v_linha := r ->> 'texto';
  else
    v_rot := 'Comissão de ' || v_mes_txt || ' ('
          || case when (r #>> '{teste,em_teste}')::boolean then 'teste'
                  else format('mês %s de %s do teste', r #>> '{teste,mes_do_teste}', r #>> '{teste,meses}') end
          || ', nada pago): ';
    v_fim := ' *comissão ' || v_mes_txt || '* mostra a conta.';
    if (r ->> 'nao_atribuida')::numeric > 0 then
      v_nao := '; ' || public._brl((r ->> 'nao_atribuida')::numeric) || ' sem dia lançado na OS para dividir';
    end if;
    select coalesce(jsonb_agg(e order by n), '[]'::jsonb) into v_tec
      from jsonb_array_elements(r -> 'tecnicos') with ordinality as x(e, n)
     where (e ->> 'diarias')::numeric > 0 or (e ->> 'comissao')::numeric > 0;
    v_n := jsonb_array_length(v_tec);

    if v_n = 0 then
      v_linha := v_rot || 'sem diária no mês' || v_nao || '.' || v_fim;
    else
      -- cada técnico; se passar de 200 caracteres, a soma com os nomes; senão, a soma só
      v_linha := v_rot || (select string_agg(format('%s — diárias %s × comissão %s', e ->> 'nome',
                                                    public._brl((e ->> 'diarias')::numeric),
                                                    public._brl((e ->> 'comissao')::numeric)), '; ' order by n)
                             from jsonb_array_elements(v_tec) with ordinality as x(e, n))
              || v_nao || '.' || v_fim;
      if char_length(v_linha) > 200 then
        v_linha := v_rot || format('diárias %s × comissão %s (%s)',
                     public._brl((select sum((e ->> 'diarias')::numeric) from jsonb_array_elements(v_tec) e)),
                     public._brl((select sum((e ->> 'comissao')::numeric) from jsonb_array_elements(v_tec) e)),
                     public._agenda_lista(array(select e ->> 'nome' from jsonb_array_elements(v_tec) with ordinality as x(e, n)
                                                 order by n), 2))
                || v_nao || '.' || v_fim;
      end if;
      if char_length(v_linha) > 200 then
        v_linha := v_rot || format('diárias %s × comissão %s',
                     public._brl((select sum((e ->> 'diarias')::numeric) from jsonb_array_elements(v_tec) e)),
                     public._brl((select sum((e ->> 'comissao')::numeric) from jsonb_array_elements(v_tec) e)))
                || v_nao || '.' || v_fim;
      end if;
    end if;
  end if;

  return jsonb_build_object('mes', v_mes, 'ate', r -> 'ate', 'primeiro_dia_util', p_hoje = v_pdu,
                            'texto', r ->> 'texto', 'linha', v_linha);
end;
$function$;

comment on function public.comissao_resumo_do_mes(date, date) is
  'Agenda de Produção (Fase 3, P5): o resumo da comissão "o maior dos dois" — {mes, ate, primeiro_dia_util, texto, linha}. Sem p_mes: o mês corrente até p_hoje, ou o mês anterior até o 1º dia útil do mês (inclusive). texto = o da conversa (comissao_tecnicos_do_mes); linha (≤ 200 caracteres) = a do fechamento do 1º dia útil: "Comissão de outubro (teste, nada pago): Roberto — diárias R$ X × comissão R$ Y; R$ Z sem dia lançado na OS para dividir. *comissão outubro* mostra a conta." SÓ A CONTA (STABLE): nada é pago nem gravado. Admin/financeiro ou service_role; senão 42501.';

revoke all on function public.comissao_resumo_do_mes(date, date) from public, anon;
grant execute on function public.comissao_resumo_do_mes(date, date) to authenticated, service_role;
