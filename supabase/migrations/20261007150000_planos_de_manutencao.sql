-- Planos de manutenção com lembretes (07/10/2026) — frente BANCO.
-- Especificação: scratchpad spec-planos-manutencao.md (decisões do dono fechadas em 07/10/2026):
--   1. lembrete ao CLIENTE sai SEMPRE com o "sim" do dono antes (a pendência nasce na edge
--      lembretes-de-revisao; esta migration só EXECUTA o envio já aprovado);
--   2. no máximo 3 mensagens por vencimento: D-21, D-7 (sem resposta), D+14 (sem resposta e sem OS);
--   3. campanha de temporada (15/09–31/10), uma por cliente por ano, também com o "sim".
--
-- O que estava errado antes: o plano só sabia "last_service_at" (gravado à mão, em UTC pela tela),
-- ninguém atualizava o plano quando a OS era concluída, e a R14 só criava uma tarefa — nada chegava
-- ao cliente. Aqui:
--   · colunas novas no plano (critério do "serviço feito", adiamento, lembrete ao cliente on/off);
--   · maintenance_plan_events: a trilha de cada ciclo (proposto, enviado, pulado, respondeu, adiou,
--     serviço feito, campanha) — é dela que a edge decide o próximo toque e a métrica conta;
--   · v_maintenance_plans_due: o vencimento e a situação calculados num lugar só (tela, motor,
--     resumo e assistente leem daqui — antes cada um calculava o seu);
--   · gatilho na OS concluída: o plano cujo critério casa com os serviços/peças da OS ganha a data
--     do serviço sozinho (data de Brasília);
--   · RPCs: registrar_servico_do_plano, adiar_plano, enviar_lembrete_de_revisao,
--     registrar_resposta_da_revisao (esta só para o whatsapp-webhook, como a da R15).
--
-- O cron da edge lembretes-de-revisao NÃO está aqui (decisão: o dono autoriza e ele é aplicado à
-- parte). O comando:
--   select cron.schedule('lembretes-de-revisao', '5 12 * * 2-4', $cron$
--     select net.http_post(
--       url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/lembretes-de-revisao',
--       headers := jsonb_build_object('Content-Type', 'application/json',
--         'x-cron-secret', (select value::text from app_settings where key = 'cron_worker_secret' limit 1)),
--       body := '{}'::jsonb, timeout_milliseconds := 60000);
--   $cron$);
--   (12:05 UTC = 09:05 de Brasília, terça a quinta.)

-- ─── 1. Colunas novas do plano ──────────────────────────────────────────────────────────────
alter table public.maintenance_plans
  add column if not exists service_system text,
  add column if not exists service_verb text,
  add column if not exists match_keywords text[],
  add column if not exists last_service_order_id uuid references public.service_orders(id) on delete set null,
  add column if not exists snoozed_until date,
  add column if not exists client_reminder_enabled boolean not null default true,
  add column if not exists source text not null default 'manual';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'maintenance_plans_source_check') then
    alter table public.maintenance_plans
      add constraint maintenance_plans_source_check check (source in ('manual', 'sugerido'));
  end if;
end $$;

comment on column public.maintenance_plans.service_system is
  'Critério do "serviço feito": OS concluída com serviço deste sistema (service_order_services.service_system) conta como o serviço do plano.';
comment on column public.maintenance_plans.service_verb is
  'Critério do "serviço feito": verbo do serviço (service_order_services.service_verb). Com service_system, os dois na mesma linha.';
comment on column public.maintenance_plans.match_keywords is
  'Critério do "serviço feito": palavras procuradas no nome do serviço da OS e no nome do produto das peças. Plano SEM critério nenhum casa com qualquer OS concluída da embarcação.';
comment on column public.maintenance_plans.snoozed_until is
  'Adiado até esta data (pelo dono ou pela resposta do cliente). Até lá, nada de lembrete.';
comment on column public.maintenance_plans.client_reminder_enabled is
  'false = este plano nunca gera lembrete ao cliente (só a tarefa interna R14).';

create index if not exists maintenance_plans_last_service_order on public.maintenance_plans (last_service_order_id)
  where last_service_order_id is not null;

drop trigger if exists update_maintenance_plans_updated_at on public.maintenance_plans;
create trigger update_maintenance_plans_updated_at
  before update on public.maintenance_plans
  for each row execute function public.update_updated_at_column();

-- ─── 2. Trilha do ciclo ─────────────────────────────────────────────────────────────────────
-- plan_id é anulável DE PROPÓSITO: a campanha de temporada vai a quem tem embarcação com serviço
-- e nenhum plano (é o caso de quase todos hoje) — o evento fica preso à embarcação e ao cliente.
-- vessel_id e client_id vão em todo evento: a resposta do cliente chega pelo telefone e a métrica
-- conta OS da embarcação depois do envio.
create table if not exists public.maintenance_plan_events (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid references public.maintenance_plans(id) on delete cascade,
  vessel_id uuid references public.vessels(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  due_on date,
  tipo text not null check (tipo in ('task_created', 'reminder_proposed', 'reminder_sent', 'reminder_skipped',
    'client_replied', 'snoozed', 'scheduled', 'serviced', 'campaign_proposed', 'campaign_sent')),
  toque smallint check (toque is null or toque in (1, 2, 3)),
  service_order_id uuid references public.service_orders(id) on delete set null,
  whatsapp_message_id uuid,
  detalhe jsonb not null default '{}'::jsonb,
  created_by uuid,
  created_at timestamptz not null default now(),
  constraint maintenance_plan_events_alvo check (plan_id is not null or vessel_id is not null)
);

comment on table public.maintenance_plan_events is
  'Trilha dos planos de manutenção (07/10/2026): due_on = o vencimento do ciclo em que o evento aconteceu; toque 1/2/3 = D-21/D-7/D+14. Campanha: plan_id nulo, toque nulo.';

create index if not exists maintenance_plan_events_plano on public.maintenance_plan_events (plan_id, due_on, tipo);
create index if not exists maintenance_plan_events_cliente on public.maintenance_plan_events (client_id, created_at desc);
create index if not exists maintenance_plan_events_tipo on public.maintenance_plan_events (tipo, created_at desc);

alter table public.maintenance_plan_events enable row level security;
drop policy if exists maintenance_plan_events_select on public.maintenance_plan_events;
create policy maintenance_plan_events_select on public.maintenance_plan_events
  for select to authenticated using (true);
drop policy if exists maintenance_plan_events_insert on public.maintenance_plan_events;
create policy maintenance_plan_events_insert on public.maintenance_plan_events
  for insert to authenticated with check (true);
revoke all on public.maintenance_plan_events from anon;
grant select, insert on public.maintenance_plan_events to authenticated;
grant all on public.maintenance_plan_events to service_role;

-- ─── 3. Ajudantes ───────────────────────────────────────────────────────────────────────────
-- O dia em Brasília. Não havia equivalente no banco: cada função fazia "at time zone" à mão.
create or replace function public._dia_br(p_quando timestamptz)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select (p_quando at time zone 'America/Sao_Paulo')::date;
$$;

-- Texto para comparar: minúsculo e sem acento (mesma tradução de _e_concordancia).
create or replace function public._texto_simples(p_texto text)
returns text
language sql
immutable
security definer
set search_path = public
as $$
  select translate(lower(coalesce(p_texto, '')), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc');
$$;

-- O vencimento do ciclo: último serviço (ou a criação do plano) + intervalo.
create or replace function public._vencimento_do_plano(p_ultimo date, p_criado timestamptz, p_meses integer)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select (coalesce(p_ultimo, public._dia_br(p_criado)) + make_interval(months => p_meses))::date;
$$;

-- A OS conta como o serviço do plano?
--   · sem critério nenhum → qualquer OS concluída da embarcação;
--   · só sistema/verbo → uma linha de serviço com esse sistema (e verbo);
--   · com palavras → uma linha de serviço do sistema/verbo (se houver) cujo NOME tem a palavra, OU
--     uma peça cujo produto tem a palavra no nome. As palavras ESTREITAM o sistema: "baterias"
--     (eletrico_dc + 'bateria') não pode zerar o plano com a instalação de um conversor DC-DC.
-- A mesma regra em TypeScript: casaComCriterio (_shared/ai/tools/planos-manutencao.ts).
create or replace function public._plano_casa_com_os(p_service_system text, p_service_verb text, p_palavras text[], p_os uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with k as (
    select public._texto_simples(btrim(x)) as palavra
      from unnest(coalesce(p_palavras, '{}'::text[])) x
     where btrim(x) <> ''
  )
  select case
    when p_service_system is null and p_service_verb is null and not exists (select 1 from k) then true
    when not exists (select 1 from k) then exists (
      select 1 from public.service_order_services s
       where s.service_order_id = p_os
         and (p_service_system is null or s.service_system = p_service_system)
         and (p_service_verb is null or s.service_verb = p_service_verb))
    else exists (
      select 1 from k
       where exists (select 1 from public.service_order_services s
                      where s.service_order_id = p_os
                        and (p_service_system is null or s.service_system = p_service_system)
                        and (p_service_verb is null or s.service_verb = p_service_verb)
                        and strpos(public._texto_simples(s.name_snapshot), k.palavra) > 0)
          or exists (select 1 from public.service_order_parts pp
                       join public.products pr on pr.id = pp.product_id
                      where pp.service_order_id = p_os
                        and strpos(public._texto_simples(pr.name), k.palavra) > 0))
  end;
$$;

-- A próxima janela de envio ao cliente: terça a quinta, 9h–11h ou 14h–17h de Brasília (pesquisa:
-- é quando o dono de barco lê e responde; nunca fim de semana nem noite). Dentro dela = agora.
create or replace function public._proxima_janela_revisao(p_agora timestamptz)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_dia date;
  v_ini timestamp;
  v_fim timestamp;
  i int;
  j int;
begin
  for i in 0..14 loop
    v_dia := v_local::date + i;
    continue when extract(isodow from v_dia) not in (2, 3, 4);
    for j in 1..2 loop
      v_ini := v_dia + case when j = 1 then time '09:00' else time '14:00' end;
      v_fim := v_dia + case when j = 1 then time '11:00' else time '17:00' end;
      if v_local < v_fim then
        return greatest(v_local, v_ini) at time zone 'America/Sao_Paulo';
      end if;
    end loop;
  end loop;
  return p_agora;
end;
$$;

-- ─── 4. A view ──────────────────────────────────────────────────────────────────────────────
-- Uma linha por plano ATIVO. `name` e `plan_name` são a mesma coisa (os dois nomes, para a tela e o
-- assistente). window_opens_on = quando a tarefa do DONO abre: advance_days antes do vencimento
-- ("avisar X dias antes" na tela; padrão 21, igual ao primeiro toque) ou o fim do adiamento. O
-- primeiro toque ao CLIENTE é fixo em D-21 e calculado pela edge lembretes-de-revisao, não daqui.
-- tem_os_agendada inclui 'approved' (OS aprovada esperando agenda também é trabalho marcado).
alter table public.maintenance_plans alter column advance_days set default 21;

create or replace view public.v_maintenance_plans_due
with (security_invoker = on) as
with base as (
  select mp.*,
         v.name as vessel_name,
         v.client_id,
         c.name as client_name,
         coalesce(nullif(btrim(c.whatsapp), ''), nullif(btrim(c.phone), '')) as client_phone,
         coalesce(c.opt_out_whatsapp, false) as opt_out,
         public._vencimento_do_plano(mp.last_service_at, mp.created_at, mp.interval_months) as next_due_on,
         public._dia_br(now()) as hoje
    from public.maintenance_plans mp
    join public.vessels v on v.id = mp.vessel_id
    left join public.clients c on c.id = v.client_id
   where mp.active
)
select b.id as plan_id,
       b.vessel_id,
       b.vessel_name,
       b.client_id,
       b.client_name,
       b.client_phone,
       b.opt_out,
       b.name as plan_name,
       b.name,
       b.scope,
       b.estimated_value,
       b.interval_months,
       b.advance_days,
       b.last_service_at,
       b.last_service_order_id,
       b.service_system,
       b.service_verb,
       b.match_keywords,
       b.client_reminder_enabled,
       b.source,
       b.notes,
       b.next_due_on,
       greatest(b.next_due_on - coalesce(b.advance_days, 21), b.snoozed_until) as window_opens_on,
       b.snoozed_until,
       (b.next_due_on - b.hoje) as dias_para_vencer,
       case
         when b.snoozed_until > b.hoje then 'adiada'
         when b.next_due_on < b.hoje then 'vencida'
         when b.next_due_on - b.hoje <= coalesce(b.advance_days, 21) then 'na_janela'
         else 'em_dia'
       end as situacao,
       (os.id is not null) as tem_os_agendada,
       os.id as os_agendada_id,
       os.service_order_number as os_agendada_numero,
       (select max(e.toque) from public.maintenance_plan_events e
         where e.plan_id = b.id and e.tipo = 'reminder_sent' and e.due_on = b.next_due_on) as ultimo_toque,
       exists (select 1 from public.maintenance_plan_events e
                where e.plan_id = b.id and e.tipo = 'client_replied' and e.due_on = b.next_due_on) as respondeu_no_ciclo
  from base b
  left join lateral (
    select s.id, s.service_order_number
      from public.service_orders s
     where s.vessel_id = b.vessel_id
       and s.status in ('scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client', 'approved')
       and (b.last_service_at is null
            or s.created_at >= (b.last_service_at::timestamp at time zone 'America/Sao_Paulo'))
     order by s.scheduled_start_at nulls last, s.created_at
     limit 1
  ) os on true;

revoke all on public.v_maintenance_plans_due from anon;
grant select on public.v_maintenance_plans_due to authenticated, service_role;

-- ─── 5. OS concluída → serviço do plano ─────────────────────────────────────────────────────
-- Uma vez por OS: só na passagem de "não concluída" para completed/invoiced (completed → invoiced
-- não conta de novo). Nunca derruba a conclusão da OS: qualquer erro aqui vira aviso no log.
create or replace function public._plano_registra_os_concluida()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dia date;
  p record;
begin
  if new.vessel_id is null
     or new.status not in ('completed', 'invoiced')
     or old.status in ('completed', 'invoiced') then
    return new;
  end if;
  begin
    v_dia := public._dia_br(coalesce(new.check_out_at, new.scheduled_end_at, now()));
    for p in
      select mp.* from public.maintenance_plans mp
       where mp.vessel_id = new.vessel_id and mp.active
       for update
    loop
      continue when not public._plano_casa_com_os(p.service_system, p.service_verb, p.match_keywords, new.id);
      -- Não volta no tempo: um serviço já registrado mais novo vale mais que esta OS.
      continue when p.last_service_at is not null and p.last_service_at > v_dia;
      update public.maintenance_plans
         set last_service_at = v_dia, last_service_order_id = new.id, snoozed_until = null
       where id = p.id;
      insert into public.maintenance_plan_events (plan_id, vessel_id, client_id, due_on, tipo, service_order_id, detalhe)
      values (p.id, new.vessel_id, new.client_id,
              public._vencimento_do_plano(p.last_service_at, p.created_at, p.interval_months),
              'serviced', new.id,
              jsonb_build_object('data', v_dia, 'anterior', p.last_service_at, 'origem', 'os_concluida',
                                 'os', new.service_order_number));
    end loop;
  exception when others then
    raise warning '[planos] OS % concluída, mas o plano não foi atualizado: %', new.service_order_number, sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists trg_plano_os_concluida on public.service_orders;
create trigger trg_plano_os_concluida
  after update of status on public.service_orders
  for each row
  when (new.status is distinct from old.status)
  execute function public._plano_registra_os_concluida();

-- ─── 6. "Serviço feito" (tela e assistente) ────────────────────────────────────────────────
-- Data de Brasília por padrão (a tela gravava a data UTC: depois das 21h virava o dia seguinte).
-- Quem pode: qualquer usuário ativo (é o que a tela permite hoje); auth.uid() ou p_autor só
-- para registrar quem fez — o assistente no WhatsApp roda sem sessão (p_autor).
create or replace function public.registrar_servico_do_plano(
  p_plano uuid, p_data date default null, p_os uuid default null, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_hoje date := public._dia_br(now());
  v_dia date := coalesce(p_data, public._dia_br(now()));
  v_p record;
  v_os record;
  v_novo date;
begin
  if v_autor is not null and not exists (select 1 from public.app_users u where u.id = v_autor and u.active) then
    raise exception 'Usuário sem permissão para registrar serviço.' using errcode = '42501';
  end if;

  select mp.id, mp.name, mp.vessel_id, mp.last_service_at, mp.created_at, mp.interval_months, mp.active,
         v.client_id, v.name as barco
    into v_p
    from public.maintenance_plans mp join public.vessels v on v.id = mp.vessel_id
   where mp.id = p_plano
   for update of mp;
  if v_p.id is null then raise exception 'Plano de manutenção não encontrado.'; end if;
  if v_dia > v_hoje then
    raise exception 'A data do serviço (%) ainda não chegou.', to_char(v_dia, 'DD/MM/YYYY');
  end if;
  if v_dia < v_hoje - 3650 then raise exception 'Data do serviço inválida (%).', to_char(v_dia, 'DD/MM/YYYY'); end if;

  if p_os is not null then
    select s.id, s.vessel_id, s.service_order_number into v_os from public.service_orders s where s.id = p_os;
    if v_os.id is null then raise exception 'OS não encontrada.'; end if;
    if v_os.vessel_id is distinct from v_p.vessel_id then
      raise exception 'A % é de outra embarcação.', v_os.service_order_number;
    end if;
  end if;

  update public.maintenance_plans
     set last_service_at = v_dia, last_service_order_id = p_os, snoozed_until = null
   where id = p_plano;

  insert into public.maintenance_plan_events (plan_id, vessel_id, client_id, due_on, tipo, service_order_id, detalhe, created_by)
  values (p_plano, v_p.vessel_id, v_p.client_id,
          public._vencimento_do_plano(v_p.last_service_at, v_p.created_at, v_p.interval_months),
          'serviced', p_os,
          jsonb_build_object('data', v_dia, 'anterior', v_p.last_service_at, 'origem', 'manual'), v_autor);

  v_novo := public._vencimento_do_plano(v_dia, v_p.created_at, v_p.interval_months);
  return jsonb_build_object(
    'ok', true, 'plano', v_p.name, 'embarcacao', v_p.barco, 'servico_em', v_dia, 'proximo_vencimento', v_novo,
    'message', 'Serviço registrado em ' || to_char(v_dia, 'DD/MM/YYYY') || ' (' || v_p.name || ' — ' || v_p.barco
               || '). Próximo vencimento: ' || to_char(v_novo, 'DD/MM/YYYY') || '.'
               || case when v_p.active then '' else ' Atenção: o plano está desligado.' end);
end;
$$;

-- ─── 7. Adiar ───────────────────────────────────────────────────────────────────────────────
create or replace function public.adiar_plano(
  p_plano uuid, p_ate date, p_motivo text default null, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_hoje date := public._dia_br(now());
  v_p record;
begin
  if v_autor is not null and not exists (select 1 from public.app_users u where u.id = v_autor and u.active) then
    raise exception 'Usuário sem permissão para adiar o plano.' using errcode = '42501';
  end if;
  select mp.id, mp.name, mp.vessel_id, mp.active, mp.last_service_at, mp.created_at, mp.interval_months,
         v.client_id, v.name as barco
    into v_p
    from public.maintenance_plans mp join public.vessels v on v.id = mp.vessel_id
   where mp.id = p_plano
   for update of mp;
  if v_p.id is null then raise exception 'Plano de manutenção não encontrado.'; end if;
  if not v_p.active then raise exception 'O plano % está desligado: não há o que adiar.', v_p.name; end if;
  if p_ate is null or p_ate <= v_hoje then raise exception 'A data para adiar tem de ser depois de hoje.'; end if;
  if p_ate > v_hoje + 400 then raise exception 'Adiar no máximo por um ano.'; end if;

  update public.maintenance_plans set snoozed_until = p_ate where id = p_plano;
  insert into public.maintenance_plan_events (plan_id, vessel_id, client_id, due_on, tipo, detalhe, created_by)
  values (p_plano, v_p.vessel_id, v_p.client_id,
          public._vencimento_do_plano(v_p.last_service_at, v_p.created_at, v_p.interval_months),
          'snoozed', jsonb_build_object('ate', p_ate, 'motivo', nullif(btrim(coalesce(p_motivo, '')), ''), 'origem', 'manual'),
          v_autor);
  return jsonb_build_object('ok', true, 'plano', v_p.name, 'embarcacao', v_p.barco, 'adiado_ate', p_ate,
    'message', v_p.name || ' — ' || v_p.barco || ': adiado até ' || to_char(p_ate, 'DD/MM/YYYY') || '. Nenhum lembrete até lá.');
end;
$$;

-- ─── 8. Envio do lembrete JÁ APROVADO pelo dono ────────────────────────────────────────────
-- Quem chama: a tool enviar_lembrete_de_revisao, depois do "sim" (a pendência nasce na edge
-- lembretes-de-revisao ou no pedido do dono ao assistente). Confere de novo, na hora do envio:
-- opt-out, telefone, lembrete desligado, OS agendada/concluída depois do último serviço — se
-- algum barrar, NÃO manda e registra reminder_skipped com o motivo (devolve error, não lança,
-- para o registro ficar). Modo de teste igual ao de pedir_confirmacao_do_agendamento.
-- p_toque 1/2/3 = D-21/D-7/D+14; 0 = campanha de temporada (p_planos pode vir vazio: aí
-- p_embarcacao diz para quem — a campanha vai também a quem não tem plano).
create or replace function public.enviar_lembrete_de_revisao(
  p_planos uuid[], p_toque smallint, p_texto text, p_autor uuid default null, p_embarcacao uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_planos uuid[] := coalesce(p_planos, '{}'::uuid[]);
  v_campanha boolean := p_toque = 0;
  v_texto text := btrim(coalesce(p_texto, ''));
  v_hoje date := public._dia_br(now());
  v_n int;
  v_clientes int;
  v_barco uuid;
  v_cli record;
  v_fone text;
  v_teste boolean;
  v_fone_teste text;
  v_destino text;
  v_motivo text;
  v_quando timestamptz;
  v_fila uuid;
  v_chave text;
  v_p record;
begin
  if v_autor is null then
    raise exception 'Lembrete ao cliente precisa de quem autorizou o envio.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.app_users u where u.id = v_autor and u.active and u.role in ('admin', 'financial')) then
    raise exception 'Só administrador ou financeiro manda lembrete de revisão ao cliente.' using errcode = '42501';
  end if;
  if p_toque is null or p_toque not in (0, 1, 2, 3) then
    raise exception 'Toque inválido (1 = D-21, 2 = D-7, 3 = D+14, 0 = campanha).';
  end if;
  if v_texto = '' then raise exception 'A mensagem está vazia.'; end if;
  if length(v_texto) > 1000 then raise exception 'Mensagem longa demais para um lembrete (máx. 1000 caracteres).'; end if;
  if cardinality(v_planos) > 5 then raise exception 'No máximo 5 planos numa mensagem.'; end if;
  if not v_campanha and cardinality(v_planos) = 0 then raise exception 'Diga de qual plano é o lembrete.'; end if;

  if cardinality(v_planos) > 0 then
    select count(*), count(distinct v.client_id) into v_n, v_clientes
      from public.maintenance_plans mp join public.vessels v on v.id = mp.vessel_id
     where mp.id = any(v_planos);
    if v_n <> cardinality(v_planos) then raise exception 'Plano de manutenção não encontrado.'; end if;
    if v_clientes > 1 then raise exception 'Uma mensagem é para UM cliente: os planos são de clientes diferentes.'; end if;
    if exists (select 1 from public.maintenance_plans where id = any(v_planos) and not active) then
      raise exception 'Um dos planos está desligado.';
    end if;
    select mp.vessel_id into v_barco from public.maintenance_plans mp where mp.id = v_planos[1];
  else
    v_barco := p_embarcacao;
  end if;
  if v_barco is null then raise exception 'Diga a embarcação da campanha.'; end if;

  select c.id, c.name, c.whatsapp, c.phone, c.opt_out_whatsapp, v.id as barco_id, v.name as barco
    into v_cli
    from public.vessels v join public.clients c on c.id = v.client_id
   where v.id = v_barco;
  if v_cli.id is null then raise exception 'Embarcação sem cliente cadastrado.'; end if;

  -- Já foi? (o mesmo toque do mesmo ciclo, ou a campanha deste ano a este cliente)
  if not v_campanha and exists (
      select 1 from public.v_maintenance_plans_due d
        join public.maintenance_plan_events e on e.plan_id = d.plan_id and e.due_on = d.next_due_on
       where d.plan_id = any(v_planos) and e.tipo = 'reminder_sent' and e.toque = p_toque) then
    return jsonb_build_object('error', 'Este lembrete (toque ' || p_toque || ') já foi enviado neste ciclo.', 'enviado', false);
  end if;
  if v_campanha and exists (
      select 1 from public.maintenance_plan_events e
       where e.client_id = v_cli.id and e.tipo = 'campaign_sent'
         and extract(year from e.created_at at time zone 'America/Sao_Paulo') = extract(year from v_hoje)) then
    return jsonb_build_object('error', 'A campanha deste ano já foi para ' || v_cli.name || '.', 'enviado', false);
  end if;

  v_fone := regexp_replace(coalesce(nullif(v_cli.whatsapp, ''), v_cli.phone, ''), '\D', '', 'g');
  if length(v_fone) in (10, 11) then v_fone := '55' || v_fone; end if;

  v_motivo := case
    when coalesce(v_cli.opt_out_whatsapp, false) then 'opt_out'
    when length(v_fone) < 12 then 'sem_telefone'
    when exists (select 1 from public.maintenance_plans where id = any(v_planos) and not client_reminder_enabled) then 'lembrete_desligado'
    when not v_campanha and exists (select 1 from public.v_maintenance_plans_due d where d.plan_id = any(v_planos) and d.tem_os_agendada) then 'os_agendada'
    -- OS concluída depois do último serviço que CASA com o plano (o gatilho não pegou: ex. OS
    -- concluída antes de o plano existir). OS de outro assunto não barra o lembrete.
    when not v_campanha and exists (
      select 1 from public.maintenance_plans mp
        join public.service_orders s on s.vessel_id = mp.vessel_id and s.status in ('completed', 'invoiced')
       where mp.id = any(v_planos)
         and public._dia_br(coalesce(s.check_out_at, s.scheduled_end_at, s.updated_at)) > coalesce(mp.last_service_at, public._dia_br(mp.created_at))
         and public._plano_casa_com_os(mp.service_system, mp.service_verb, mp.match_keywords, s.id)) then 'os_concluida'
    when v_campanha and exists (
      select 1 from public.service_orders s where s.vessel_id = v_barco
         and s.status in ('scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client', 'approved')) then 'os_agendada'
    -- Campanha a quem acabou de ser atendido (90 dias) é mensagem à toa.
    when v_campanha and exists (
      select 1 from public.service_orders s where s.vessel_id = v_barco and s.status in ('completed', 'invoiced')
         and public._dia_br(coalesce(s.check_out_at, s.scheduled_end_at, s.updated_at)) > v_hoje - 90) then 'servico_recente'
    else null
  end;

  if v_motivo is not null then
    if cardinality(v_planos) > 0 then
      insert into public.maintenance_plan_events (plan_id, vessel_id, client_id, due_on, tipo, toque, detalhe, created_by)
      select mp.id, mp.vessel_id, v_cli.id, public._vencimento_do_plano(mp.last_service_at, mp.created_at, mp.interval_months),
             'reminder_skipped', nullif(p_toque, 0), jsonb_build_object('motivo', v_motivo, 'campanha', v_campanha), v_autor
        from public.maintenance_plans mp where mp.id = any(v_planos);
    else
      insert into public.maintenance_plan_events (vessel_id, client_id, tipo, detalhe, created_by)
      values (v_barco, v_cli.id, 'reminder_skipped', jsonb_build_object('motivo', v_motivo, 'campanha', true), v_autor);
    end if;
    return jsonb_build_object('enviado', false, 'pulado', v_motivo,
      'error', 'Não mandei: ' || case v_motivo
        when 'opt_out' then v_cli.name || ' pediu para não receber WhatsApp.'
        when 'sem_telefone' then v_cli.name || ' está sem telefone válido no cadastro.'
        when 'lembrete_desligado' then 'o lembrete ao cliente está desligado neste plano.'
        when 'os_agendada' then 'já há OS aberta/agendada para a ' || v_cli.barco || '.'
        when 'os_concluida' then 'já há OS concluída deste serviço depois do último registrado — confira e marque "serviço feito".'
        when 'servico_recente' then 'a ' || v_cli.barco || ' foi atendida nos últimos 90 dias.'
        else v_motivo end);
  end if;

  v_teste := coalesce((select value::text from public.app_settings where key = 'wa_test_mode'), 'false') in ('true', '"true"');
  v_fone_teste := regexp_replace(coalesce((select value::text from public.app_settings where key = 'wa_test_number'), ''), '\D', '', 'g');
  if v_teste and v_fone_teste = '' then raise exception 'Modo de teste ligado sem número de teste configurado.'; end if;
  v_destino := case when v_teste then v_fone_teste else v_fone end;

  -- Fora da janela útil, a fila segura até a próxima; mensagens do mesmo dia saem espaçadas.
  v_quando := public._proxima_janela_revisao(now())
    + (select count(*) from public.whatsapp_send_queue q where q.source = 'revisao-plano' and q.status = 'pending') * interval '4 minutes';

  v_chave := case
    when v_campanha then 'campanha:' || v_cli.id || ':' || extract(year from v_hoje)
    else 'revisao:' || array_to_string(array(select x::text from unnest(v_planos) x order by 1), ',') || ':'
         || (select public._vencimento_do_plano(mp.last_service_at, mp.created_at, mp.interval_months)
               from public.maintenance_plans mp where mp.id = v_planos[1]) || ':' || p_toque
  end || case when v_teste then ':teste' else '' end;

  insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority, scheduled_for, dedupe_key)
  values (v_destino, v_texto, 'revisao-plano', coalesce(v_planos[1], v_barco), 3, v_quando, v_chave)
  on conflict do nothing
  returning id into v_fila;
  if v_fila is null then
    return jsonb_build_object('error', 'Este lembrete já está na fila de envio.', 'enviado', false);
  end if;

  insert into public.ai_comms_log (tipo, audiencia, entity_kind, entity_id, phone, message_preview, status)
  values ('reativacao', 'cliente', 'client', v_cli.id, v_destino, left(v_texto, 300), 'sent');

  if cardinality(v_planos) > 0 then
    for v_p in
      select mp.id, mp.vessel_id, public._vencimento_do_plano(mp.last_service_at, mp.created_at, mp.interval_months) as venc
        from public.maintenance_plans mp where mp.id = any(v_planos)
    loop
      insert into public.maintenance_plan_events (plan_id, vessel_id, client_id, due_on, tipo, toque, detalhe, created_by)
      values (v_p.id, v_p.vessel_id, v_cli.id, v_p.venc,
              case when v_campanha then 'campaign_sent' else 'reminder_sent' end, nullif(p_toque, 0),
              jsonb_build_object('fila_id', v_fila, 'texto', v_texto, 'telefone', v_destino, 'teste', v_teste,
                                 'agendado_para', v_quando, 'planos', to_jsonb(v_planos)),
              v_autor);
    end loop;
  else
    insert into public.maintenance_plan_events (vessel_id, client_id, tipo, detalhe, created_by)
    values (v_barco, v_cli.id, 'campaign_sent',
            jsonb_build_object('fila_id', v_fila, 'texto', v_texto, 'telefone', v_destino, 'teste', v_teste,
                               'agendado_para', v_quando, 'ano', extract(year from v_hoje)),
            v_autor);
  end if;

  return jsonb_build_object(
    'ok', true, 'enviado', true, 'teste', v_teste, 'cliente', v_cli.name, 'embarcacao', v_cli.barco,
    'agendado_para', v_quando, 'mensagem', v_texto,
    'enviado_para', case when v_teste then 'o número de TESTE (' || v_fone_teste || ')' else v_destino end,
    'message', case
      when v_teste then 'Lembrete na fila (modo de teste: vai para o número de teste).'
      when v_quando > now() + interval '2 minutes' then 'Lembrete para ' || v_cli.name || ' na fila: sai '
        || to_char(v_quando at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24"h"MI') || ' (janela de terça a quinta, 9h–11h/14h–17h).'
      else 'Lembrete para ' || v_cli.name || ' na fila: sai em instantes.' end);
end;
$$;

-- ─── 9. Resposta do cliente (só o whatsapp-webhook chama) ──────────────────────────────────
-- Vale para quem teve lembrete/campanha nos últimos 21 dias (8 últimos dígitos do telefone).
--   PARAR (palavra sozinha) → opt-out do cliente. Por quê aqui: o lembrete diz "responda PARAR",
--     e o classificador do webhook (reply-router) só reconhece frases como "pare de mandar" — o
--     "PARAR" sozinho passava batido. Vale só para quem recebeu o lembrete.
--   Concordância curta (_e_concordancia) → tarefa "Agendar revisão" ao admin + sino.
--   Data (p_data, lida em TypeScript por _shared/revisao/data-da-resposta.ts, que tem teste) →
--     adia o plano até lá + tarefa nessa data + sino.
--   Outro texto → registra e avisa no sino (só a primeira resposta depois do envio).
-- Cada caso é registrado uma vez por envio (mesma intenção não duplica tarefa nem sino).
create or replace function public.registrar_resposta_da_revisao(
  p_telefone text, p_texto text, p_mensagem uuid default null, p_data date default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_txt text := btrim(regexp_replace(regexp_replace(public._texto_simples(p_texto), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'));
  v_hoje date := public._dia_br(now());
  v_cliente uuid;
  v_nome text;
  v_envio timestamptz;
  v_intencao text;
  v_planos text;
  v_barcos text;
  v_barco uuid;
  v_titulo text;
  v_corpo text;
  v_admin uuid;
  v_n int := 0;
  e record;
begin
  if length(v_fone) < 8 or btrim(coalesce(p_texto, '')) = '' then
    return jsonb_build_object('registrou', false);
  end if;

  select ev.client_id, max(ev.created_at) into v_cliente, v_envio
    from public.maintenance_plan_events ev
    join public.clients c on c.id = ev.client_id
   where ev.tipo in ('reminder_sent', 'campaign_sent')
     and ev.created_at > now() - interval '21 days'
     and right(regexp_replace(coalesce(nullif(c.whatsapp, ''), c.phone, ''), '\D', '', 'g'), 8) = right(v_fone, 8)
   group by ev.client_id
   order by max(ev.created_at) desc
   limit 1;
  if v_cliente is null then return jsonb_build_object('registrou', false); end if;

  if p_mensagem is not null and exists (
      select 1 from public.maintenance_plan_events where tipo = 'client_replied' and whatsapp_message_id = p_mensagem) then
    return jsonb_build_object('registrou', false, 'repetida', true);
  end if;

  v_intencao := case
    when v_txt ~ '^(parar|pare|stop|sair|descadastrar)$' then 'parar'
    when public._e_concordancia(p_texto) then 'sim'
    when p_data is not null and p_data > v_hoje and p_data <= v_hoje + 400 then 'data'
    else 'outro'
  end;

  -- A mesma intenção já registrada depois deste envio não gera outra tarefa/sino.
  if exists (select 1 from public.maintenance_plan_events
              where client_id = v_cliente and tipo = 'client_replied' and created_at >= v_envio
                and (detalhe ->> 'intencao' = v_intencao or (v_intencao = 'outro'))) then
    return jsonb_build_object('registrou', false, 'motivo', 'ja_registrado');
  end if;

  select name into v_nome from public.clients where id = v_cliente;

  -- Os planos (ou a embarcação da campanha) daquele envio: gravados na mesma transação = mesmo created_at.
  for e in
    select ev.plan_id, ev.vessel_id, ev.due_on, mp.name as plano, v.name as barco
      from public.maintenance_plan_events ev
      left join public.maintenance_plans mp on mp.id = ev.plan_id
      left join public.vessels v on v.id = ev.vessel_id
     where ev.client_id = v_cliente and ev.created_at = v_envio and ev.tipo in ('reminder_sent', 'campaign_sent')
  loop
    v_n := v_n + 1;
    v_barco := coalesce(v_barco, e.vessel_id);
    v_planos := coalesce(v_planos || ' + ', '') || coalesce(e.plano, 'revisão elétrica (campanha)');
    if v_barcos is null then v_barcos := e.barco;
    elsif strpos(v_barcos, coalesce(e.barco, '')) = 0 then v_barcos := v_barcos || ', ' || e.barco; end if;

    insert into public.maintenance_plan_events (plan_id, vessel_id, client_id, due_on, tipo, whatsapp_message_id, detalhe)
    values (e.plan_id, e.vessel_id, v_cliente, e.due_on, 'client_replied', p_mensagem,
            jsonb_build_object('intencao', v_intencao, 'texto', left(btrim(p_texto), 300),
                               'data', case when v_intencao = 'data' then p_data end, 'envio_em', v_envio));

    if v_intencao = 'data' and e.plan_id is not null then
      update public.maintenance_plans set snoozed_until = p_data where id = e.plan_id and active;
      insert into public.maintenance_plan_events (plan_id, vessel_id, client_id, due_on, tipo, whatsapp_message_id, detalhe)
      values (e.plan_id, e.vessel_id, v_cliente, e.due_on, 'snoozed', p_mensagem,
              jsonb_build_object('ate', p_data, 'origem', 'cliente', 'texto', left(btrim(p_texto), 300)));
    end if;
  end loop;
  if v_n = 0 then return jsonb_build_object('registrou', false); end if;

  if v_intencao = 'parar' then
    update public.clients set opt_out_whatsapp = true where id = v_cliente;
  end if;

  if v_intencao in ('sim', 'data') then
    select u.id into v_admin from public.app_users u where u.role = 'admin' and u.active order by u.created_at limit 1;
    v_titulo := 'Agendar revisão: ' || v_planos || ' — ' || coalesce(v_barcos, 'embarcação')
      || case when v_intencao = 'sim' then ' (cliente respondeu SIM)'
              else ' (cliente pediu ' || to_char(p_data, 'DD/MM') || ')' end;
    insert into public.agenda_tasks (title, kind, status, priority, source, automation_key, assignee_user_id, due_at,
                                     related_entity_type, related_entity_id, client_id, notes)
    values (v_titulo, 'task', 'pending', 'high', 'automation',
            'revisao:resp:' || v_cliente || ':' || extract(epoch from v_envio)::bigint,
            v_admin,
            case when v_intencao = 'data' then (p_data + time '08:00') at time zone 'America/Sao_Paulo' else now() end,
            'vessel', v_barco, v_cliente,
            coalesce(v_nome, 'Cliente') || ' respondeu ao lembrete: "' || left(btrim(p_texto), 200) || '"')
    on conflict do nothing;
  end if;

  v_corpo := '"' || left(btrim(p_texto), 120) || '" — ' || case v_intencao
    when 'parar' then 'pediu para não receber mais WhatsApp (marquei no cadastro).'
    when 'sim' then 'tarefa "Agendar revisão" criada na sua agenda.'
    when 'data' then 'plano adiado até ' || to_char(p_data, 'DD/MM/YYYY') || ' e tarefa criada para esse dia.'
    else 'confira e responda.' end;
  insert into public.app_notifications (user_id, type, title, body, navigate_to)
  select u.id, 'revisao_resposta',
         coalesce(v_nome, 'Cliente') || ' respondeu ao lembrete de revisão (' || coalesce(v_barcos, 'embarcação') || ')',
         v_corpo, case when v_barco is not null then '/v2/vessels/' || v_barco else '/agenda' end
    from public.app_users u where u.role = 'admin' and u.active;

  return jsonb_build_object('registrou', true, 'intencao', v_intencao, 'cliente', v_nome);
end;
$$;

-- ─── 10. Interruptores (padrão ligado) ─────────────────────────────────────────────────────
insert into public.app_settings (key, value, description) values
  ('lembretes_revisao_ativo', 'on', 'Lembretes de revisão ao cliente (sempre com o "sim" do dono antes). off = a edge lembretes-de-revisao não propõe nada.'),
  ('campanha_temporada_ativa', 'on', 'Campanha de temporada (15/09–31/10): uma mensagem por cliente por ano, com o "sim" do dono.')
on conflict (key) do nothing;

-- ─── 11. Permissões ─────────────────────────────────────────────────────────────────────────
revoke all on function public._dia_br(timestamptz) from public, anon;
revoke all on function public._texto_simples(text) from public, anon;
revoke all on function public._vencimento_do_plano(date, timestamptz, integer) from public, anon;
revoke all on function public._plano_casa_com_os(text, text, text[], uuid) from public, anon;
revoke all on function public._proxima_janela_revisao(timestamptz) from public, anon;
revoke all on function public._plano_registra_os_concluida() from public, anon, authenticated;
revoke all on function public.registrar_servico_do_plano(uuid, date, uuid, uuid) from public, anon;
revoke all on function public.adiar_plano(uuid, date, text, uuid) from public, anon;
revoke all on function public.enviar_lembrete_de_revisao(uuid[], smallint, text, uuid, uuid) from public, anon;
-- Como a registrar_confirmacao_do_cliente (R15): só o webhook (service_role). Aberta a
-- authenticated, qualquer usuário forjaria a resposta de um cliente.
revoke all on function public.registrar_resposta_da_revisao(text, text, uuid, date) from public, anon, authenticated;

grant execute on function public._dia_br(timestamptz) to authenticated, service_role;
grant execute on function public._texto_simples(text) to authenticated, service_role;
grant execute on function public._vencimento_do_plano(date, timestamptz, integer) to authenticated, service_role;
grant execute on function public._plano_casa_com_os(text, text, text[], uuid) to authenticated, service_role;
grant execute on function public._proxima_janela_revisao(timestamptz) to authenticated, service_role;
grant execute on function public.registrar_servico_do_plano(uuid, date, uuid, uuid) to authenticated, service_role;
grant execute on function public.adiar_plano(uuid, date, text, uuid) to authenticated, service_role;
grant execute on function public.enviar_lembrete_de_revisao(uuid[], smallint, text, uuid, uuid) to authenticated, service_role;
grant execute on function public.registrar_resposta_da_revisao(text, text, uuid, date) to service_role;

-- Prova: anon não executa nenhuma função nova, nem lê a view/tabela nova.
do $$
declare
  f text;
begin
  foreach f in array array[
    'public._dia_br(timestamptz)',
    'public._texto_simples(text)',
    'public._vencimento_do_plano(date, timestamptz, integer)',
    'public._plano_casa_com_os(text, text, text[], uuid)',
    'public._proxima_janela_revisao(timestamptz)',
    'public._plano_registra_os_concluida()',
    'public.registrar_servico_do_plano(uuid, date, uuid, uuid)',
    'public.adiar_plano(uuid, date, text, uuid)',
    'public.enviar_lembrete_de_revisao(uuid[], smallint, text, uuid, uuid)',
    'public.registrar_resposta_da_revisao(text, text, uuid, date)'
  ] loop
    if has_function_privilege('anon', f, 'execute') then
      raise exception 'anon ainda executa %', f;
    end if;
  end loop;
  if has_function_privilege('authenticated', 'public.registrar_resposta_da_revisao(text, text, uuid, date)', 'execute') then
    raise exception 'authenticated não pode registrar resposta de cliente';
  end if;
  if has_table_privilege('anon', 'public.v_maintenance_plans_due', 'select') then
    raise exception 'anon ainda lê v_maintenance_plans_due';
  end if;
  if has_table_privilege('anon', 'public.maintenance_plan_events', 'select') then
    raise exception 'anon ainda lê maintenance_plan_events';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261007150000', 'planos_de_manutencao')
on conflict do nothing;
