-- ═══════════════════════════════════════════════════════════════════════════
-- A LINHA da ordem ganha onde guardar o fiscal
--
-- ═══ O BURACO ESTRUTURAL ═══
--
-- `service_order_services` não tinha nenhuma coluna fiscal. Todo o fiscal
-- (national_tax_code, cnae, iss_rate, fiscal_verb) vive em `services`, o
-- catálogo. Uma linha digitada à mão tem `service_id` nulo — não existe cadastro
-- onde o dado possa morar.
--
-- Medido em 25/08: 33 linhas assim, em 10 ordens (22% de todas as linhas de
-- serviço). Seis delas em OS já concluída, R$ 2.525 impedidos de virar NFS-e.
-- A tela de emissão dizia "linha avulsa — vincule ao catálogo na OS", e vincular
-- não existia em lugar nenhum do sistema. Beco sem saída.
--
-- ═══ POR QUE UMA COLUNA SÓ, E NÃO CINCO ═══
--
-- Bastaria copiar as cinco colunas fiscais do serviço para a linha. Não é o que
-- se quer: os dez verbos fiscais têm valores IDÊNTICOS (140101 / 14.01 /
-- CNAE 3317102 / ISS 3% / sem retenção — a regra da contadora, 18/08/2026).
-- Escolher o verbo não altera imposto nenhum; ele só LIGA a herança que já
-- existe. Cinco colunas seriam cinco lugares para o mesmo valor divergir.
--
-- ═══ A LINHA É FALLBACK, NÃO OVERRIDE ═══
--
-- `resolveLineFiscal` (no edge) só consulta o verbo da linha quando o catálogo
-- não resolveu. Serviço com código próprio continua mandando. O contrário
-- inverteria o princípio que o teste de paridade protege: verbo genérico não
-- revoga o que a contabilidade cadastrou à mão.
--
-- ═══ EXPOSIÇÃO PÚBLICA — DECIDIDO ANTES DE CRIAR ═══
--
-- `PublicServiceOrderView` e `carregarPDFData` leem `service_order_services`
-- com `select('*')`, então esta coluna passa a viajar para o link público
-- automaticamente. É aceitável e foi verificado: `fiscal_verb` é um slug de
-- classificação ('instalacao', 'reparo') cujos efeitos — código de serviço e
-- alíquota — já aparecem impressos na própria nota que o cliente recebe. Não há
-- nada nela que o documento já não diga.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

alter table public.service_order_services
  add column if not exists fiscal_verb text;

-- FK com nome explícito: o embed do PostgREST depende do nome da constraint, e
-- deixá-lo ao acaso é como um `select` de embed quebra meses depois.
alter table public.service_order_services
  drop constraint if exists sos_fiscal_verb_fk;
alter table public.service_order_services
  add constraint sos_fiscal_verb_fk
  foreign key (fiscal_verb) references public.service_fiscal_verbs(verb_slug)
  on update cascade on delete set null;

create index if not exists idx_sos_fiscal_verb
  on public.service_order_services(fiscal_verb)
  where fiscal_verb is not null;

comment on column public.service_order_services.fiscal_verb is
  'Verbo fiscal DESTA LINHA, para quando não há serviço de catálogo por trás
   (linha digitada à mão). É FALLBACK: só vale quando o catálogo não resolve o
   código de tributação — verbo genérico não passa por cima do cadastro que a
   contabilidade fez. Os dez verbos têm hoje valores idênticos (14.01 / ISS 3%),
   então escolhê-lo não altera imposto: ele liga a herança que já existe.';

commit;
