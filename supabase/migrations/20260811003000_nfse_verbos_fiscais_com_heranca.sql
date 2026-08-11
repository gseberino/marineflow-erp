-- [F-NFSE-03] Cadastro fiscal por VERBO, com herança — a chave que o levantamento provou.
--
-- Por que verbo e não categoria (medido em [F-NFSE-02], não presumido):
--
--   services.service_verb    242 de 243 (99,6%)  ← preenchido
--   services.service_system  236 de 243 (97%)
--   services.category          5 de 243 (2%)     ← um backfill aqui atingiria CINCO serviços
--
-- E não é só disponibilidade de dado: a LC 116 organiza serviço por ATIVIDADE. "Instalação de
-- sistema elétrico" e "instalação de refrigeração" são o mesmo item da lista; "instalação" e
-- "reparo" do MESMO sistema são itens diferentes. O verbo é a chave por natureza — estar
-- preenchido em 242 de 243 confirma a escolha, não a motiva.
--
-- ═══ DUAS DECISÕES DE DESENHO QUE MERECEM EXPLICAÇÃO ═══
--
-- 1. `service_fiscal_verbs` ESTENDE `service_verbs`; não repete o catálogo.
--    O catálogo de verbos já existe desde 03/08 (`service_verbs`, 10 linhas, com `name` e
--    `is_fieldwork`) e `services.service_verb` já é FK dele. Criar uma segunda tabela com os
--    mesmos dez slugs daria duas fontes para a mesma verdade: renomear um verbo em uma e não
--    na outra é o tipo de divergência que ninguém percebe até a nota sair errada. Aqui a PK
--    É a FK — uma linha fiscal por verbo existente, nem mais nem menos.
--
-- 2. `services.fiscal_verb` é coluna SEPARADA de `services.service_verb`.
--    Parece redundante e não é. O verbo operacional decide o ROTEIRO do técnico; o verbo
--    fiscal decide o CÓDIGO DE TRIBUTAÇÃO. Eles coincidem hoje em quase tudo, mas precisam
--    poder divergir — e o caso que força isso já existe: "MÃO DE OBRA" (R$ 12.000, terceira
--    maior linha de faturamento) está em `logistica`, classificação que o NOVO-012 registra
--    como suspeita. Com uma coluna só, seria preciso escolher entre quebrar o roteiro ou
--    aceitar o código fiscal duvidoso. Com duas, o serviço fica operacionalmente classificado
--    e fiscalmente EM BRANCO — que é a verdade: ninguém sabe ainda.
--
-- ═══ NENHUM CÓDIGO FISCAL É INVENTADO AQUI ═══
--
-- As dez linhas nascem com `default_national_tax_code`, `default_cnae` e `default_iss_rate`
-- NULOS. A contabilidade ainda não respondeu, e código de tributação errado declara à
-- prefeitura serviço que não foi prestado — ninguém confere isso depois da nota autorizada.
-- Esta migration monta a ESTRUTURA e o caminho de herança; preencher é outro passo, com os
-- números que a contabilidade devolver.
--
-- Reversível: apagar `service_fiscal_verbs` e a coluna `fiscal_verb` devolve o estado atual.
-- Nenhum dado existente é sobrescrito — o backfill só ESCREVE em coluna nova.

-- ── a. A tabela fiscal do verbo ──────────────────────────────────────────────
create table if not exists public.service_fiscal_verbs (
  verb_slug text primary key
    references public.service_verbs(slug) on update cascade on delete restrict,
  default_national_tax_code text,
  default_service_code      text,
  default_cnae              text,
  default_iss_rate          numeric,
  default_iss_withheld      boolean,
  notes                     text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.service_fiscal_verbs is
  'Cadastro fiscal por verbo de servico. O servico herda daqui quando nao tem valor proprio
   (ver public.resolve_service_fiscal). Dez linhas — contra 243 se fosse por servico.';
comment on column public.service_fiscal_verbs.default_national_tax_code is
  'Codigo de tributacao NACIONAL, 6 digitos sem pontuacao (ex.: 140101). Evita E0310. NAO e o
   municipal sem os pontos: "14.01" corresponde a 140101, nao a 140100.';
comment on column public.service_fiscal_verbs.default_iss_rate is
  'Aliquota de ISS em PERCENTUAL (5 = 5%), nao fracao. E a aliquota de Itajai — so a
   contabilidade sabe.';
comment on column public.service_fiscal_verbs.notes is
  'Onde a contabilidade registra por que este codigo, e nao outro. E o unico lugar em que essa
   justificativa fica gravada.';

-- Mesmos formatos que `services` guarda, pela mesma razao: um CNAE de 6 digitos so apareceria
-- como rejeicao da prefeitura, minutos depois e longe da causa. `is null or` mantem a linha
-- vazia possivel — que e exatamente como todas nascem.
alter table public.service_fiscal_verbs
  drop constraint if exists sfv_national_tax_code_formato;
alter table public.service_fiscal_verbs
  add constraint sfv_national_tax_code_formato
  check (default_national_tax_code is null or default_national_tax_code ~ '^[0-9]{6}$');

alter table public.service_fiscal_verbs
  drop constraint if exists sfv_cnae_formato;
alter table public.service_fiscal_verbs
  add constraint sfv_cnae_formato
  check (default_cnae is null or default_cnae ~ '^[0-9]{7}$');

alter table public.service_fiscal_verbs
  drop constraint if exists sfv_iss_rate_faixa;
alter table public.service_fiscal_verbs
  add constraint sfv_iss_rate_faixa
  check (default_iss_rate is null or (default_iss_rate >= 0 and default_iss_rate <= 100));

-- Uma linha por verbo do catalogo, TODAS com campos fiscais nulos.
insert into public.service_fiscal_verbs (verb_slug)
select slug from public.service_verbs
on conflict (verb_slug) do nothing;

alter table public.service_fiscal_verbs enable row level security;

create policy service_fiscal_verbs_read on public.service_fiscal_verbs
  for select to authenticated
  using (not (select public.is_external_seller(auth.uid())));

create policy service_fiscal_verbs_write on public.service_fiscal_verbs
  for all to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

revoke all on public.service_fiscal_verbs from anon;

create trigger set_updated_at_service_fiscal_verbs
  before update on public.service_fiscal_verbs
  for each row execute function public.update_updated_at_column();

-- ── b. O vinculo fiscal do servico ───────────────────────────────────────────
alter table public.services
  add column if not exists fiscal_verb text;

alter table public.services drop constraint if exists services_fiscal_verb_fk;
alter table public.services
  add constraint services_fiscal_verb_fk
  foreign key (fiscal_verb) references public.service_fiscal_verbs(verb_slug)
  on update cascade on delete set null;

comment on column public.services.fiscal_verb is
  'Verbo FISCAL do servico — de onde ele herda codigo de tributacao, CNAE e ISS. Separado de
   service_verb (que decide o roteiro do tecnico) de proposito: um servico pode estar
   operacionalmente classificado e fiscalmente em branco. NULL = sem heranca; so o valor
   proprio vale.';

create index if not exists idx_services_fiscal_verb
  on public.services(fiscal_verb) where fiscal_verb is not null;

-- ── c. Backfill: o verbo operacional vira o verbo fiscal ─────────────────────
-- Exceto "MÃO DE OBRA" (NOVO-012). Sao R$ 12.000 num verbo (`logistica`) que sugere
-- transporte/deslocamento. Sem confirmacao de quem conhece o servico prestado, ela fica SEM
-- verbo fiscal — e a emissao vai exigir o codigo na mao, que e o comportamento correto para
-- um servico cuja atividade ninguem confirmou.
--
-- O `not exists` sobre `service_fiscal_verbs` e redundante hoje (semeamos os 10 acima) e
-- barato; protege o dia em que um verbo for desativado do catalogo fiscal.
update public.services s
   set fiscal_verb = s.service_verb
 where s.service_verb is not null
   and s.fiscal_verb is null
   and exists (select 1 from public.service_fiscal_verbs f where f.verb_slug = s.service_verb)
   and upper(btrim(translate(s.name, 'ÃÁÂÀÇÉÊÍÓÔÕÚ', 'AAAACEEIOOOU'))) <> 'MAO DE OBRA';

-- ── d. O resolvedor: COALESCE(proprio, verbo) ────────────────────────────────
-- Fonte da verdade do que vai NA NOTA. O espelho em TypeScript
-- (_shared/fiscal/service-fiscal.ts) repete esta ordem, e um teste de paridade falha se as
-- duas divergirem — espelho que diverge em silencio ja causou bug real neste sistema.
--
-- Por que resolver em tempo de LEITURA em vez de copiar o codigo para as 243 linhas: gravar
-- copiaria o codigo em massa, e a primeira correcao da contabilidade exigiria um segundo
-- backfill para desfazer. Resolvido aqui, corrigir UMA linha de default corrige o catalogo
-- inteiro. E a mesma razao pela qual o produto resolve default_ncm em vez de copia-lo.
--
-- ATENCAO — `iss_withheld` NAO herda, e isso e proposital. A coluna em `services` e
-- `not null default false`, entao um COALESCE nunca chegaria ao verbo: toda linha ja tem
-- `false` gravado. Distinguir "explicitamente sem retencao" de "nunca preenchido" exigiria
-- decidir o que significam os `false` que ja existem — decisao de retencao tributaria, nao
-- de schema. Fica como esta (valor do servico manda) ate a contabilidade responder.
create or replace function public.resolve_service_fiscal(p_service_id uuid)
returns table (
  national_tax_code text,
  service_code      text,
  cnae              text,
  iss_rate          numeric,
  iss_withheld      boolean,
  code_source       text
)
language sql
stable
security invoker
set search_path = public
as $fn$
  select
    coalesce(s.national_tax_code, f.default_national_tax_code),
    coalesce(s.service_code,      f.default_service_code),
    coalesce(s.cnae,              f.default_cnae),
    coalesce(s.iss_rate,          f.default_iss_rate),
    s.iss_withheld,
    case
      when s.national_tax_code is not null            then 'proprio'
      when f.default_national_tax_code is not null    then 'verbo'
      else 'nenhum'
    end
  from public.services s
  left join public.service_fiscal_verbs f on f.verb_slug = s.fiscal_verb
  where s.id = p_service_id;
$fn$;

revoke all on function public.resolve_service_fiscal(uuid) from public, anon;
grant execute on function public.resolve_service_fiscal(uuid) to authenticated;

-- ── e. A visao que a tela de servicos consome ────────────────────────────────
-- `sem_codigo_fiscal` olha o valor EFETIVO, nao `services.national_tax_code`. Um filtro que
-- olhasse so a coluna propria mostraria 238 pendentes para sempre, mesmo com os defaults
-- preenchidos e tudo emitindo normalmente — um alarme que ninguem pode desligar.
create or replace view public.v_services_fiscal_efetivo
with (security_invoker = on) as
select
  s.id,
  s.name,
  s.active,
  s.service_verb,
  s.fiscal_verb,
  coalesce(s.national_tax_code, f.default_national_tax_code) as national_tax_code_efetivo,
  coalesce(s.service_code,      f.default_service_code)      as service_code_efetivo,
  coalesce(s.cnae,              f.default_cnae)              as cnae_efetivo,
  coalesce(s.iss_rate,          f.default_iss_rate)          as iss_rate_efetivo,
  s.iss_withheld                                             as iss_withheld_efetivo,
  case
    when s.national_tax_code is not null         then 'proprio'
    when f.default_national_tax_code is not null then 'verbo'
    else 'nenhum'
  end                                                        as code_source,
  (coalesce(s.national_tax_code, f.default_national_tax_code) is null) as sem_codigo_fiscal
from public.services s
left join public.service_fiscal_verbs f on f.verb_slug = s.fiscal_verb;

comment on view public.v_services_fiscal_efetivo is
  'Codigo fiscal EFETIVO de cada servico (proprio ou herdado do verbo) e de onde ele veio.
   sem_codigo_fiscal olha o efetivo — o filtro da tela depende disso para nao acusar pendencia
   em servico que ja resolve pelo verbo.';

revoke all on public.v_services_fiscal_efetivo from anon;
grant select on public.v_services_fiscal_efetivo to authenticated;
