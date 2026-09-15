-- "Deixar a IA acompanhar" — Fase 0 (contraparte genérica) + base da Fase 1 (copiloto).
-- Dossiê: plans/marineflow-ia-acompanha.md. Decisões do dono (30/08/2026): nome do botão
-- "Deixar a IA acompanhar"; copiloto por 30 dias (o dono aprova cada mensagem); 3 toques
-- para FORNECEDOR e 2 para CLIENTE; começar pelos dois casos (entrega de fornecedor e
-- orçamento parado com cliente). Ordem de compra ficou fora (o módulo nunca foi usado).
--
-- A missão é a PERSEGUIÇÃO de um compromisso; o fato perseguido continua sendo o fio solto
-- (entity_open_loops) ou a tarefa/orçamento de origem. Por isso ela carrega a própria
-- contraparte (tipo/id/telefone/rótulo, congelados na criação) — agenda_tasks não tem
-- supplier_id, e o caso emblemático (Vanderlei) é fornecedor.
--
-- Princípio 1: o ERP responde antes da pessoa — o runner relê o critério (criterio_erp) antes
-- de todo toque e fecha sem falar com ninguém. Princípio 3: teto baixo de toques; estourou,
-- devolve para o dono. Uma missão ativa por contato (trava do HubSpot).

create table if not exists public.ai_followup_missions (
  id uuid primary key default gen_random_uuid(),
  objetivo text not null,
  contraparte_tipo text not null check (contraparte_tipo in ('client','supplier','lead')),
  contraparte_id uuid,
  contraparte_phone text not null,
  contraparte_label text not null,
  origem_tipo text not null check (origem_tipo in ('agenda_task','quote','open_loop','manual')),
  origem_id uuid,
  service_order_id uuid references public.service_orders(id) on delete set null,
  open_loop_id uuid references public.entity_open_loops(id) on delete set null,
  criterio_erp text not null default 'manual'
    check (criterio_erp in ('task_done','quote_decided','open_loop_resolved','manual')),
  prazo_final timestamptz,
  max_toques integer not null default 3 check (max_toques between 1 and 6),
  toques_feitos integer not null default 0,
  proximo_toque_em timestamptz,
  ultimo_toque_em timestamptz,
  autonomia text not null default 'draft' check (autonomia in ('draft','auto')),
  status text not null default 'active'
    check (status in ('active','waiting_reply','resolved','escalated','cancelled','expired')),
  resolucao text,
  resolucao_evidencia text,
  resolvida_em timestamptz,
  criada_por uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.ai_followup_missions is
  'Missão de acompanhamento: a IA cobra um terceiro (fornecedor/cliente) sobre um compromisso até resolver. Copiloto: cada toque passa pelo portão de aprovação.';
comment on column public.ai_followup_missions.criterio_erp is
  'Como o ERP prova que resolveu sem falar com ninguém: task_done (tarefa concluída), quote_decided (orçamento aprovado/rejeitado), open_loop_resolved (fio solto fechado), manual.';
comment on column public.ai_followup_missions.status is
  'active = cobrando · waiting_reply = o terceiro respondeu, o dono decide · resolved · escalated (teto/prazo) · cancelled · expired';

-- Uma missão ativa por contato: duas cobranças simultâneas para a mesma pessoa é ruído.
create unique index if not exists ai_followup_missions_uma_ativa_por_contato
  on public.ai_followup_missions (contraparte_phone) where status in ('active','waiting_reply');
create index if not exists ai_followup_missions_status_proximo
  on public.ai_followup_missions (status, proximo_toque_em);
create index if not exists ai_followup_missions_origem
  on public.ai_followup_missions (origem_tipo, origem_id);

drop trigger if exists set_updated_at_ai_followup_missions on public.ai_followup_missions;
create trigger set_updated_at_ai_followup_missions
  before update on public.ai_followup_missions
  for each row execute function public.set_updated_at_now();

create table if not exists public.ai_followup_events (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.ai_followup_missions(id) on delete cascade,
  tipo text not null check (tipo in ('created','erp_check','erp_resolved','draft','touch_sent','reply','skipped','escalated','resolved','cancelled','expired','note')),
  conteudo text,
  classificacao text,
  evidencia text,
  pending_action_id uuid references public.ai_operator_pending_actions(id) on delete set null,
  whatsapp_message_id uuid references public.whatsapp_messages(id) on delete set null,
  meta jsonb not null default '{}'::jsonb,
  created_by uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now()
);
comment on table public.ai_followup_events is
  'Trilha da missão: cada toque, rascunho, resposta e decisão. Toda mensagem que sai é auditável aqui.';
create index if not exists ai_followup_events_mission
  on public.ai_followup_events (mission_id, created_at desc);

-- ── RLS: equipe interna lê e cria; vendedor externo fica de fora; anon nunca ────────
alter table public.ai_followup_missions enable row level security;
alter table public.ai_followup_events enable row level security;

drop policy if exists "followup_missions_select" on public.ai_followup_missions;
create policy "followup_missions_select" on public.ai_followup_missions
  for select to authenticated using (not public.is_external_seller(auth.uid()));
drop policy if exists "followup_missions_insert" on public.ai_followup_missions;
create policy "followup_missions_insert" on public.ai_followup_missions
  for insert to authenticated with check (not public.is_external_seller(auth.uid()));
drop policy if exists "followup_missions_update" on public.ai_followup_missions;
create policy "followup_missions_update" on public.ai_followup_missions
  for update to authenticated
  using (not public.is_external_seller(auth.uid()))
  with check (not public.is_external_seller(auth.uid()));

drop policy if exists "followup_events_select" on public.ai_followup_events;
create policy "followup_events_select" on public.ai_followup_events
  for select to authenticated using (not public.is_external_seller(auth.uid()));
drop policy if exists "followup_events_insert" on public.ai_followup_events;
create policy "followup_events_insert" on public.ai_followup_events
  for insert to authenticated with check (not public.is_external_seller(auth.uid()));

revoke all on public.ai_followup_missions from anon;
revoke all on public.ai_followup_events from anon;

-- ── Kill switch e teto diário (dossiê §10 e §6) ──────────────────────────────────
insert into public.app_settings (key, value)
values ('followup_missions_enabled', 'true'), ('followup_missions_daily_cap', '10')
on conflict (key) do nothing;

-- ── Criar missão a partir da origem (tarefa, orçamento, fio solto ou avulsa) ──────
create or replace function public.create_followup_mission(
  p_origem_tipo text,
  p_origem_id uuid,
  p_objetivo text,
  p_prazo_final timestamptz default null,
  p_contraparte_tipo text default null,
  p_contraparte_id uuid default null,
  p_phone text default null,
  p_label text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_tipo text := p_contraparte_tipo;
  v_id uuid := p_contraparte_id;
  v_cli uuid; v_so uuid; v_loop uuid;
  v_tipo_loop text; v_id_loop uuid;
  v_criterio text := 'manual';
  v_raw_db text; v_label_db text; v_optout boolean := false;
  v_raw text; v_phone text; v_label text;
  v_max integer; v_prox timestamptz; v_missao uuid;
begin
  if public.is_external_seller(auth.uid()) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if coalesce(trim(p_objetivo), '') = '' then
    raise exception 'Diga o que a IA deve acompanhar (objetivo da missão).';
  end if;

  -- A origem diz como o ERP prova que resolveu, e sugere a contraparte quando o chamador
  -- não a informou.
  if p_origem_tipo = 'quote' then
    select so.id, so.client_id into v_so, v_cli from public.service_orders so where so.id = p_origem_id;
    if v_so is null then raise exception 'Orçamento não encontrado.'; end if;
    v_criterio := 'quote_decided';
    if v_tipo is null then v_tipo := 'client'; v_id := v_cli; end if;
  elsif p_origem_tipo = 'agenda_task' then
    select t.client_id,
           case when t.related_entity_type = 'service_order' then t.related_entity_id end
      into v_cli, v_so
    from public.agenda_tasks t where t.id = p_origem_id;
    if not found then raise exception 'Tarefa não encontrada.'; end if;
    v_criterio := 'task_done';
    if v_tipo is null and v_cli is not null then v_tipo := 'client'; v_id := v_cli; end if;
  elsif p_origem_tipo = 'open_loop' then
    select l.entity_type, l.entity_id, l.service_order_id into v_tipo_loop, v_id_loop, v_so
    from public.entity_open_loops l where l.id = p_origem_id;
    if not found then raise exception 'Fio solto não encontrado.'; end if;
    v_loop := p_origem_id;
    v_criterio := 'open_loop_resolved';
    if v_tipo is null then v_tipo := v_tipo_loop; v_id := v_id_loop; end if;
  elsif p_origem_tipo = 'manual' then
    null;
  else
    raise exception 'Origem inválida: %', p_origem_tipo;
  end if;

  if v_tipo = 'client' and v_id is not null then
    select coalesce(nullif(c.whatsapp, ''), c.phone), coalesce(nullif(c.display_name, ''), c.name), coalesce(c.opt_out_whatsapp, false)
      into v_raw_db, v_label_db, v_optout
    from public.clients c where c.id = v_id;
  elsif v_tipo = 'supplier' and v_id is not null then
    select s.phone, coalesce(nullif(s.display_name, ''), nullif(s.trade_name, ''), s.name), coalesce(s.opt_out_whatsapp, false)
      into v_raw_db, v_label_db, v_optout
    from public.suppliers s where s.id = v_id;
  end if;
  if v_tipo is null then v_tipo := 'lead'; end if;

  v_raw := coalesce(nullif(trim(p_phone), ''), v_raw_db);
  v_label := coalesce(nullif(trim(p_label), ''), v_label_db, v_raw);
  if v_optout then
    raise exception 'Este contato pediu para não receber mensagens (opt-out) — a IA não vai cobrá-lo.';
  end if;
  v_phone := public.wa_normalize_phone(v_raw);
  if coalesce(v_phone, '') = '' then
    raise exception 'Contato sem telefone válido para WhatsApp.';
  end if;

  -- Decisão do dono (30/08): fornecedor atrasado é rotina (3 toques); cliente cobrado demais
  -- é venda perdida (2).
  v_max := case when v_tipo = 'supplier' then 3 else 2 end;
  -- Cadência contada para trás do prazo (D-7); sem prazo, começa agora — quem está parado
  -- já está atrasado.
  v_prox := case when p_prazo_final is null then now()
                 else greatest(now(), p_prazo_final - interval '7 days') end;

  begin
    insert into public.ai_followup_missions
      (objetivo, contraparte_tipo, contraparte_id, contraparte_phone, contraparte_label,
       origem_tipo, origem_id, service_order_id, open_loop_id, criterio_erp, prazo_final,
       max_toques, proximo_toque_em, criada_por)
    values
      (trim(p_objetivo), v_tipo, v_id, v_phone, v_label,
       p_origem_tipo, p_origem_id, v_so, v_loop, v_criterio, p_prazo_final,
       v_max, v_prox, auth.uid())
    returning id into v_missao;
  exception when unique_violation then
    raise exception 'Já existe uma missão ativa para este contato — a IA acompanha um assunto de cada vez com cada pessoa.';
  end;

  insert into public.ai_followup_events (mission_id, tipo, conteudo, created_by)
  values (v_missao, 'created', trim(p_objetivo), auth.uid());

  return v_missao;
end;
$$;

create or replace function public.cancel_followup_mission(p_id uuid, p_motivo text default null)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare v_ok integer;
begin
  update public.ai_followup_missions
     set status = 'cancelled', resolucao = coalesce(p_motivo, 'cancelada pelo dono'), resolvida_em = now(),
         proximo_toque_em = null
   where id = p_id and status in ('active','waiting_reply','escalated');
  get diagnostics v_ok = row_count;
  if v_ok > 0 then
    insert into public.ai_followup_events (mission_id, tipo, conteudo, created_by)
    values (p_id, 'cancelled', p_motivo, auth.uid());
  end if;
  return v_ok > 0;
end;
$$;

-- Chamada pelo webhook do WhatsApp (service role): o terceiro respondeu → a missão para de
-- tocar e espera o dono. A resposta é DADO, não comando: aqui ela só é registrada.
create or replace function public.followup_registrar_resposta(p_phone text, p_body text, p_message_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_missao uuid;
begin
  select id into v_missao
  from public.ai_followup_missions
  where contraparte_phone = public.wa_normalize_phone(p_phone)
    and status in ('active','waiting_reply')
  limit 1;
  if v_missao is null then return null; end if;

  insert into public.ai_followup_events (mission_id, tipo, conteudo, whatsapp_message_id)
  values (v_missao, 'reply', left(coalesce(p_body, ''), 2000), p_message_id);
  update public.ai_followup_missions
     set status = 'waiting_reply', proximo_toque_em = null
   where id = v_missao;
  return v_missao;
end;
$$;

revoke all on function public.create_followup_mission(text, uuid, text, timestamptz, text, uuid, text, text) from public, anon;
grant execute on function public.create_followup_mission(text, uuid, text, timestamptz, text, uuid, text, text) to authenticated, service_role;
revoke all on function public.cancel_followup_mission(uuid, text) from public, anon;
grant execute on function public.cancel_followup_mission(uuid, text) to authenticated, service_role;
revoke all on function public.followup_registrar_resposta(text, text, uuid) from public, anon, authenticated;
grant execute on function public.followup_registrar_resposta(text, text, uuid) to service_role;

-- ── Cron: o runner acorda de hora em hora; a janela (seg-sex 9-18h) é decidida nele ────
select cron.schedule(
  'ai-followup-runner',
  '15 * * * *',
  $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-followup-runner',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $cron$
)
where not exists (select 1 from cron.job where jobname = 'ai-followup-runner');

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md).
insert into supabase_migrations.schema_migrations (version, name)
values ('20260914130000', 'ia_acompanha_missoes')
on conflict (version) do nothing;
