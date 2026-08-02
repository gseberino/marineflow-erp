-- ═══════════════════════════════════════════════════════════════════════════
-- Sistemas viram catálogo — o dono cria categoria sem depender de código
-- Plano: plans/marineflow-execucao-os-roteiro.md, seção 10-ter (P27-P29)
--
-- Pedido do dono (02/08): "poderíamos incluir opção de adicionar uma nova
-- categoria, para depois incluir passos e roteiros, pois notei que alguns
-- serviços faltam categorias adequadas."
--
-- Hoje os sete sistemas estão escritos à mão em CINCO lugares: o CHECK de
-- `services`, o CHECK de `service_survey_templates`, o CASE de
-- service_system_label(), e duas listas no frontend. Criar "Ar comprimido"
-- exigia migration — ou seja, exigia mim.
--
-- A chave primária é o próprio slug ('eletrico_dc'), de propósito: as colunas
-- existentes já guardam esse texto, então os CHECKs viram FK sem migrar um
-- único dado.
--
-- `is_physical` separa o sistema que tem risco e merece bloco de segurança
-- daquele que só existe para dizer "isto não toca nada" (mão de obra, frete).
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.service_systems (
  slug text primary key,
  name text not null,
  short_name text,
  is_physical boolean not null default true,
  sort integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.service_systems is
  'Catálogo de sistemas (categorias técnicas). O sistema traz a abertura e o
   fechamento de segurança do roteiro; criar um sem escrever esses blocos deixa
   os serviços dele sem preparação — a tela avisa.';
comment on column public.service_systems.is_physical is
  'false = não toca sistema físico (mão de obra, frete, fora de escopo). Não
   recebe bloco de abertura porque não há o que desligar.';

insert into public.service_systems (slug, name, short_name, is_physical, sort) values
  ('eletrico_dc',  'Elétrico DC (12/24V)',   'Elétrico DC',   true,  10),
  ('eletrico_ac',  'Elétrico AC (110/220V)', 'Elétrico AC',   true,  20),
  ('gas',          'Gás GLP',                'Gás GLP',       true,  30),
  ('hidraulico',   'Hidráulico',             'Hidráulico',    true,  40),
  ('eletronico',   'Eletrônico / dados',     'Eletrônico',    true,  50),
  ('refrigeracao', 'Refrigeração',           'Refrigeração',  true,  60),
  ('mecanico',     'Mecânico',               'Mecânico',      true,  70),
  ('estrutural',   'Estrutural',             'Estrutural',    true,  80),
  ('nenhum',       'Não toca sistema físico','Sem sistema',   false, 900)
on conflict (slug) do nothing;

alter table public.service_systems enable row level security;

create policy service_systems_read on public.service_systems
  for select to authenticated
  using (not (select public.is_external_seller(auth.uid())));

-- Só quem administra o catálogo cria categoria: ela decide o roteiro de
-- segurança de todos os serviços que a usarem.
create policy service_systems_write on public.service_systems
  for all to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

create trigger set_updated_at_service_systems
  before update on public.service_systems
  for each row execute function public.update_updated_at_column();

-- ─── Os CHECKs viram FK ─────────────────────────────────────────────────────
-- Lista fechada espalhada é a armadilha que já custou caro três vezes neste
-- projeto (suggestion_type, origin de passo, agenda_tasks). Com FK, acrescentar
-- categoria é um INSERT.
alter table public.services drop constraint if exists services_system_check;
alter table public.services
  add constraint services_system_fk
  foreign key (service_system) references public.service_systems(slug)
  on update cascade;

alter table public.service_survey_templates drop constraint if exists survey_tpl_system_check;
alter table public.service_survey_templates
  add constraint survey_tpl_system_fk
  foreign key (applies_to_system) references public.service_systems(slug)
  on update cascade;

alter table public.service_step_blocks
  add constraint step_blocks_system_fk
  foreign key (applies_to_system) references public.service_systems(slug)
  on update cascade;

-- ─── O tradutor de nomes passa a ler do catálogo ────────────────────────────
-- Deixa de ser IMMUTABLE porque agora consulta tabela; STABLE basta para o uso
-- dentro da geração de roteiro.
create or replace function public.service_system_label(p_system text)
returns text language sql stable set search_path = public as $fn$
  select coalesce(
    (select coalesce(ss.short_name, ss.name) from public.service_systems ss where ss.slug = p_system),
    p_system);
$fn$;

revoke all on function public.service_system_label(text) from public, anon;
grant execute on function public.service_system_label(text) to authenticated;

-- ─── Quais categorias estão prontas para uso ────────────────────────────────
-- Categoria sem abertura e sem fechamento não protege ninguém: os serviços dela
-- receberiam o corpo do verbo e nenhuma segurança, em silêncio. Esta view é o
-- que a tela usa para marcar a categoria como incompleta.
create or replace view public.v_service_systems_status
with (security_invoker = on) as
select ss.slug, ss.name, ss.short_name, ss.is_physical, ss.sort, ss.active,
  (select count(*) from public.service_step_blocks b
    where b.applies_to_system = ss.slug and b.block_role = 'abertura' and b.active) as passos_abertura,
  (select count(*) from public.service_step_blocks b
    where b.applies_to_system = ss.slug and b.block_role = 'fechamento' and b.active) as passos_fechamento,
  (select count(*) from public.service_survey_templates t
    where t.applies_to_system = ss.slug and t.active) as perguntas,
  (select count(*) from public.services s
    where s.service_system = ss.slug and s.active) as servicos
from public.service_systems ss;

revoke all on public.v_service_systems_status from anon;
grant select on public.v_service_systems_status to authenticated;
