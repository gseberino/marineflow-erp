-- Jornada de trabalho e apuração do que pagar a funcionário e freelancer.
-- Plano: plans/marineflow-jornada-e-pagamento-de-equipe.md
--
-- POR QUE ESTAS TABELAS, se `time_entries` já existe: `time_entries.service_order_id` é NOT NULL,
-- então só há lugar para hora colada a uma OS. Dia de oficina, deslocamento entre serviços e
-- diária não têm onde ser registrados — e é por isso que o custo real de mão de obra nunca fecha.
--
-- A separação central: JORNADA é o que a pessoa trabalhou (base do que ela RECEBE); hora de OS é
-- o gasto num serviço (base do que o cliente PAGA). Uma jornada de 8h pode conter 5h em duas OS,
-- 1h de deslocamento e 2h de oficina.
--
-- NÃO é registro de ponto legal (REP-P): a Portaria 671/2021 só obriga acima de 20 empregados e a
-- HBR tem 3 ativos. Isto é controle gerencial — não emite espelho de ponto nem comprovante com fé
-- de registro. Passando de 20 empregados, é outro projeto.

-- ---------------------------------------------------------------------------
-- 1. work_profiles — como cada pessoa é paga
-- ---------------------------------------------------------------------------
create table if not exists public.work_profiles (
  id                    uuid primary key default gen_random_uuid(),

  -- Funcionário tem login (app_users); freelancer é favorecido (payees, que já existe e já
  -- guarda documento e PIX). Exatamente um dos dois — ver o CHECK abaixo.
  app_user_id           uuid references public.app_users(id) on delete cascade,
  payee_id              uuid references public.payees(id)    on delete cascade,

  tipo_vinculo          text not null check (tipo_vinculo in ('clt','diarista','freelancer','pj','socio')),
  modo_pagamento        text not null check (modo_pagamento in ('hora','diaria','mensal','empreitada')),

  valor_hora            numeric(12,2),
  valor_diaria          numeric(12,2),
  valor_mensal          numeric(12,2),

  -- Abaixo deste total de horas no dia, paga meia diária. Nulo = não existe meia diária.
  meia_diaria_ate_horas numeric(4,2),

  jornada_diaria_horas  numeric(4,2) not null default 8,
  divisor_mensal        integer      not null default 220,   -- CLT: salário / 220

  -- Percentuais legais como PADRÃO, não como verdade: convenção coletiva pode elevar.
  pct_hora_extra        numeric(5,2) not null default 50,
  pct_noturno           numeric(5,2) not null default 20,
  pct_domingo           numeric(5,2) not null default 100,
  paga_dsr              boolean      not null default false, -- só CLT

  vigencia_inicio       date not null default current_date,
  vigencia_fim          date,

  observacao            text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint work_profiles_um_titular check (
    (app_user_id is not null and payee_id is null) or
    (app_user_id is null and payee_id is not null)
  ),
  constraint work_profiles_vigencia_coerente check (
    vigencia_fim is null or vigencia_fim >= vigencia_inicio
  ),
  -- Cada modo exige o seu valor. Sem isto, um perfil "por hora" sem valor_hora só aparece
  -- na hora de pagar, quando já não dá para perguntar.
  constraint work_profiles_valor_do_modo check (
    (modo_pagamento = 'hora'       and valor_hora   is not null) or
    (modo_pagamento = 'diaria'     and valor_diaria is not null) or
    (modo_pagamento = 'mensal'     and valor_mensal is not null) or
    (modo_pagamento = 'empreitada')
  )
);

-- Um perfil vigente por titular: perfis com vigência aberta não podem se sobrepor.
create unique index if not exists work_profiles_um_vigente_por_user
  on public.work_profiles (app_user_id) where vigencia_fim is null and app_user_id is not null;
create unique index if not exists work_profiles_um_vigente_por_payee
  on public.work_profiles (payee_id)    where vigencia_fim is null and payee_id is not null;

comment on table public.work_profiles is
  'Como cada pessoa e paga, com vigencia. Mudar o valor-hora hoje nao altera o que ja foi pago: fecha-se o perfil antigo e abre-se outro.';

-- ---------------------------------------------------------------------------
-- 2. work_shifts — a jornada. Sem OS obrigatória: é essa a lacuna que existe hoje.
-- ---------------------------------------------------------------------------
create table if not exists public.work_shifts (
  id                uuid primary key default gen_random_uuid(),
  work_profile_id   uuid not null references public.work_profiles(id) on delete restrict,

  data              date not null,
  inicio            timestamptz,
  fim               timestamptz,
  intervalo_minutos integer not null default 0 check (intervalo_minutos >= 0),

  -- duracao_minutos é preenchida pelo trigger quando há início e fim; em 'diaria' o que vale é o
  -- dia, não o relógio, então pode ficar nula.
  duracao_minutos   integer check (duracao_minutos >= 0),

  tipo              text not null default 'normal'
                    check (tipo in ('normal','diaria','folga','falta','atestado','feriado')),
  origem            text not null default 'painel'
                    check (origem in ('whatsapp','painel','agente','importado')),
  status            text not null default 'rascunho'
                    check (status in ('rascunho','aprovado','pago')),

  observacao        text,
  registrado_por    uuid references public.app_users(id),
  aprovado_por      uuid references public.app_users(id),
  aprovado_em       timestamptz,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint work_shifts_fim_depois_do_inicio check (fim is null or inicio is null or fim >= inicio),
  -- Aprovado sem quem aprovou é rastro perdido — e aqui vira dinheiro depois.
  constraint work_shifts_aprovacao_tem_autor check (
    status = 'rascunho' or (aprovado_por is not null and aprovado_em is not null)
  )
);

create index if not exists work_shifts_por_perfil_data on public.work_shifts (work_profile_id, data desc);
create index if not exists work_shifts_abertos on public.work_shifts (work_profile_id) where fim is null;
create index if not exists work_shifts_por_status on public.work_shifts (status, data desc);

comment on table public.work_shifts is
  'Jornada trabalhada, independente de OS. Base do que a PESSOA recebe; time_entries continua sendo a base do que o CLIENTE paga.';

-- A hora de OS passa a poder apontar para o turno que a contém. Opcional de proposito: nada do
-- que existe hoje quebra, e passa a ser possivel perguntar quantas das 8h do dia foram cobraveis.
alter table public.time_entries
  add column if not exists shift_id uuid references public.work_shifts(id) on delete set null;
create index if not exists time_entries_por_shift on public.time_entries (shift_id) where shift_id is not null;

-- ---------------------------------------------------------------------------
-- 3. payroll_periods / payroll_lines — a apuração
-- ---------------------------------------------------------------------------
create table if not exists public.payroll_periods (
  id          uuid primary key default gen_random_uuid(),
  de          date not null,
  ate         date not null,
  descricao   text,
  status      text not null default 'aberto' check (status in ('aberto','fechado','pago')),
  fechado_por uuid references public.app_users(id),
  fechado_em  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint payroll_periods_intervalo check (ate >= de)
);

create table if not exists public.payroll_lines (
  id                  uuid primary key default gen_random_uuid(),
  payroll_period_id   uuid not null references public.payroll_periods(id) on delete cascade,
  work_profile_id     uuid not null references public.work_profiles(id)   on delete restrict,

  -- Memória de cálculo: um valor sem a conta ao lado gera discussão que ninguém resolve depois.
  horas_normais       numeric(8,2) not null default 0,
  horas_extras        numeric(8,2) not null default 0,
  horas_noturnas      numeric(8,2) not null default 0,
  horas_domingo       numeric(8,2) not null default 0,
  diarias_inteiras    numeric(6,2) not null default 0,
  diarias_meias       numeric(6,2) not null default 0,

  valor_normais       numeric(12,2) not null default 0,
  valor_extras        numeric(12,2) not null default 0,
  valor_noturnas      numeric(12,2) not null default 0,
  valor_domingo       numeric(12,2) not null default 0,
  valor_diarias       numeric(12,2) not null default 0,
  valor_mensal        numeric(12,2) not null default 0,
  valor_comissoes     numeric(12,2) not null default 0,
  valor_dsr           numeric(12,2) not null default 0,
  descontos           numeric(12,2) not null default 0,

  valor_bruto         numeric(12,2) not null default 0,
  retencoes           numeric(12,2) not null default 0,
  valor_liquido       numeric(12,2) not null default 0,

  -- Freelancer emite NFS-e desde 01/2026 (o RPA saiu de cena): aqui guarda-se a nota RECEBIDA.
  nfse_numero         text,
  nfse_valor          numeric(12,2),

  detalhamento        jsonb,       -- turno a turno, para a conta ser auditável
  payable_id          uuid references public.payables(id) on delete set null,
  observacao          text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint payroll_lines_uma_por_perfil unique (payroll_period_id, work_profile_id)
);

create index if not exists payroll_lines_por_periodo on public.payroll_lines (payroll_period_id);

comment on table public.payroll_lines is
  'Apuracao por pessoa no periodo, com a memoria de calculo aberta. payable_id liga no trilho que ja existe (commissions -> payables).';

-- ---------------------------------------------------------------------------
-- 4. Duração calculada no banco — não no cliente
-- ---------------------------------------------------------------------------
create or replace function public.calc_shift_duration()
returns trigger language plpgsql as $$
begin
  if new.inicio is not null and new.fim is not null then
    new.duracao_minutos := greatest(
      0,
      (extract(epoch from (new.fim - new.inicio)) / 60)::integer - coalesce(new.intervalo_minutos, 0)
    );
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_calc_shift_duration on public.work_shifts;
create trigger trg_calc_shift_duration
  before insert or update on public.work_shifts
  for each row execute function public.calc_shift_duration();

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists trg_touch_work_profiles on public.work_profiles;
create trigger trg_touch_work_profiles before update on public.work_profiles
  for each row execute function public.touch_updated_at();
drop trigger if exists trg_touch_payroll_periods on public.payroll_periods;
create trigger trg_touch_payroll_periods before update on public.payroll_periods
  for each row execute function public.touch_updated_at();
drop trigger if exists trg_touch_payroll_lines on public.payroll_lines;
create trigger trg_touch_payroll_lines before update on public.payroll_lines
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 5. RLS — salário é dado sensível: cada um vê o próprio, admin/financeiro veem todos
-- ---------------------------------------------------------------------------
alter table public.work_profiles  enable row level security;
alter table public.work_shifts    enable row level security;
alter table public.payroll_periods enable row level security;
alter table public.payroll_lines  enable row level security;

-- Quem é admin ou financeiro. `is_admin` já existe; financeiro é lido de app_users.
create or replace function public.pode_ver_folha(_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.app_users u
    where u.id = _user_id and u.active and u.role in ('admin','financial')
  );
$$;

-- work_profiles: o titular vê o seu; admin/financeiro veem todos. Só admin escreve — valor de
-- pagamento não se altera sozinho.
create policy work_profiles_read on public.work_profiles
  for select to authenticated
  using (public.pode_ver_folha(auth.uid()) or app_user_id = auth.uid());
create policy work_profiles_write on public.work_profiles
  for all to authenticated
  using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- work_shifts: cada um enxerga a própria jornada; admin/financeiro enxergam a de todos.
create policy work_shifts_read on public.work_shifts
  for select to authenticated
  using (
    public.pode_ver_folha(auth.uid())
    or exists (select 1 from public.work_profiles p
               where p.id = work_shifts.work_profile_id and p.app_user_id = auth.uid())
  );

-- Registrar a PRÓPRIA jornada, e só enquanto rascunho. Depois de aprovado, só admin mexe —
-- senão o registro muda depois de virar dinheiro.
create policy work_shifts_insert_proprio on public.work_shifts
  for insert to authenticated
  with check (
    public.pode_ver_folha(auth.uid())
    or (status = 'rascunho'
        and exists (select 1 from public.work_profiles p
                    where p.id = work_profile_id and p.app_user_id = auth.uid()))
  );
create policy work_shifts_update_proprio on public.work_shifts
  for update to authenticated
  using (
    public.pode_ver_folha(auth.uid())
    or (status = 'rascunho'
        and exists (select 1 from public.work_profiles p
                    where p.id = work_shifts.work_profile_id and p.app_user_id = auth.uid()))
  )
  with check (
    public.pode_ver_folha(auth.uid())
    or (status = 'rascunho'
        and exists (select 1 from public.work_profiles p
                    where p.id = work_shifts.work_profile_id and p.app_user_id = auth.uid()))
  );
create policy work_shifts_delete on public.work_shifts
  for delete to authenticated using (public.is_admin(auth.uid()));

-- Apuração: quem vê folha. Fechar período é só admin.
create policy payroll_periods_read on public.payroll_periods
  for select to authenticated using (public.pode_ver_folha(auth.uid()));
create policy payroll_periods_write on public.payroll_periods
  for all to authenticated
  using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

create policy payroll_lines_read on public.payroll_lines
  for select to authenticated
  using (
    public.pode_ver_folha(auth.uid())
    or exists (select 1 from public.work_profiles p
               where p.id = payroll_lines.work_profile_id and p.app_user_id = auth.uid())
  );
create policy payroll_lines_write on public.payroll_lines
  for all to authenticated
  using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- Tabela nova nasce acessível a anon por privilégio padrão. Fechar na MESMA migration.
revoke all on public.work_profiles   from anon;
revoke all on public.work_shifts     from anon;
revoke all on public.payroll_periods from anon;
revoke all on public.payroll_lines   from anon;
revoke all on function public.pode_ver_folha(uuid) from anon;

grant select, insert, update on public.work_shifts to authenticated;
grant select on public.work_profiles, public.payroll_periods, public.payroll_lines to authenticated;
