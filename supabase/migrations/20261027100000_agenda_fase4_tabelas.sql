-- Agenda de Produção, Fase 4 ("Material em sincronia com o fornecedor"), pacote P1: a base — os parâmetros e os três modos
-- novos, o prazo dito por fornecedor, o vínculo de linha da OC, o original da previsão, as 3 tabelas do material, as listas
-- fechadas ampliadas e a view das OCs vivas com o prazo de agenda_config.
-- Spec: scratchpad agenda-pesquisa/spec-fase4.md (§3, §4). Decisões do dono 23/10 (Autonomia: "pede ao fornecedor que
-- confirme o prazo (modelo)"; dinheiro e compra são críticos). Depende das Fases 1, 2 e 3 inteiras (20261024160000 ..
-- 20261026101000).
--
-- ═══ DDL — OK NOMEADO ═══ (3 tabelas novas, vazias; 26 parâmetros em agenda_config; 13 colunas novas em 3 tabelas, todas
-- nulas ou com DEFAULT; 1 gatilho novo em os_material; 5 listas fechadas ampliadas; a view v_oc_itens_a_caminho recriada)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: o dono não preenche OC. A Fase 4 lê o que já chega (a NF-e no e-mail, o Pix ao fornecedor, a conversa do
-- fornecedor no WhatsApp) e transforma cada sinal em previsão ou numa pergunta curta. Esta migration só cria o lugar de cada
-- coisa; quem escreve são as RPCs das próximas migrations da fase (100100 a 100600). Tudo nasce desligado e a migration de
-- dado 20261027101000 (P6, OK nomeado) põe os três modos em sombra.
--
-- O QUE MUDA:
--   1. agenda_config: modo_material, modo_detector e modo_fornecedor (a linha nasce 'desligado'; o DEFAULT da coluna vira
--      'sombra', como as Fases 2 e 3 fizeram) e 23 parâmetros da nota, do Pix, do prazo longo, do detector e da mensagem ao
--      fornecedor, cada um com CHECK por nome. O DEFAULT é o único lugar do número. oc_viva_dias é o "60 dias" que estava
--      escrito no corpo da view (Fase 0). Nenhum prazo novo: os prazos por classe continuam em prazo_classe_du e
--      importacao_dias (Fase 1).
--   2. suppliers: modalidade, prazo_dias_uteis, prazo_dias_corridos, prazo_fonte ('dono'; Fase 6: 'medido'),
--      prazo_informado_em, prazo_trecho — o que o DONO disse de cada fornecedor. Sem isso vale o chute pela cidade/UF.
--   3. purchase_order_items: service_order_part_id e service_order_service_id (a linha da OS que a linha da OC compra;
--      ON DELETE SET NULL), no máximo um dos dois, com índice parcial em cada.
--   4. material_remessas (a NF-e do e-mail no nível da NOTA: o despacho e a previsão), material_sinais (o que o detector leu
--      na conversa do fornecedor) e agenda_fornecedor_mensagens (toda mensagem ao fornecedor, mandada ou só registrada).
--      Nenhuma se apaga; só as colunas de estado mudam (gatilhos).
--   5. os_material: comprado_fonte, previsao_original_fonte, previsao_original_em, remessa_id; e o gatilho
--      _os_material_previsao_original: a 1ª previsão fica guardada SEMPRE, qualquer que seja o caminho (rascunho do dono,
--      sincronização, nota, detector, OC); a compra nova depois de a linha voltar a faltar começa um original novo e o de
--      antes vai ao histórico.
--   6. Listas fechadas: agenda_perguntas.tipo + nfe_vincular, pix_material, previsao_fornecedor, fornecedor_cadastro,
--      fornecedores_prazo (nenhum crítico: a coluna gerada critica não muda); agenda_acoes.tipo + material, fornecedor;
--      agenda_acoes.origem + fornecedor, nota; agenda_rascunho.tipo + fornecedor; agenda_vigia_rodadas.rotina + material.
--   7. v_oc_itens_a_caminho: o "60 dias" passa a agenda_config.oc_viva_dias, e as duas colunas de vínculo de linha no fim.
--   8. Portas: RLS ligada nas 3 tabelas; só leitura TO authenticated (admin/financeiro); revoke de public, anon e
--      authenticated; escrita só pelas RPCs security definer das próximas migrations (e por service_role).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase4_base.sql):
--   · suppliers_prazo_coerente: como a spec escrevia ("prazo_dias_uteis is null or (modalidade <> 'importacao' and …)"), a
--     linha com prazo e SEM modalidade passava (null <> 'importacao' é nulo, e CHECK nulo aceita). O CHECK exige a
--     modalidade junto de qualquer prazo.
--   · O original sem fonte: as Fases 1–3 escrevem previsao_original sem saber de previsao_original_fonte (a coluna é nova).
--     O gatilho completa a fonte (a da previsão; sem ela, a do fato informado; sem as duas, 'oc' — a única previsão que o
--     sistema grava sozinho é a da OC) e o dia; as linhas que já existirem quando esta migration rodar recebem a mesma
--     regra antes do CHECK (o dia fica nulo: não se sabe quando foi).
--   · A compra nova: o original de antes vai ao histórico ANTES da entrada que o caminho da escrita acrescentou na mesma
--     mudança — "historico -> -1" continua sendo o evento (os testes das Fases 1–3 leem assim).
--   · material_sinais.whatsapp_message_id é ON DELETE CASCADE como a spec pede, mas o sinal não se apaga (gatilho): na
--     prática a mensagem do WhatsApp que gerou um sinal não pode mais ser apagada. Nenhum caminho de produção apaga
--     mensagem (só os testes dos comprovantes, com telefone próprio).
--
-- O QUE NÃO MUDA: nenhum comportamento até as próximas migrations. A view devolve as mesmas linhas com o mesmo
-- conta_como_ja_pedido (60 dias = o DEFAULT de oc_viva_dias) e duas colunas a mais no fim; o gatilho do original só guarda
-- o que já era guardado na 1ª previsão; os modos nascem desligados na linha. Nenhum cron, nenhuma tela, nenhuma função de
-- borda.
--
-- ORDEM DE LIGAR: depois das Fases 1, 2 e 3 inteiras aplicadas (fila-do-dono/fase1-oks.md, fase2-oks.md, fase3-oks.md);
-- antes de 20261027100100 (o prazo do fornecedor e a prontidão, que leem as colunas novas). Aplicar sozinha não muda nada
-- para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase4_base.sql (begin/rollback; cada CHECK recusa uma linha errada, o
-- gatilho do original em todos os caminhos de escrita, as tabelas novas não se apagam, RLS, anon sem privilégio). Na
-- bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261027100100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261027100000_agenda_fase4_tabelas.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261027100000', 'agenda_fase4_tabelas');"
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$ (os de lista fechada: drop if exists + add), create
-- table/index if not exists, create or replace function/view, drop trigger/policy if exists + create.

-- ── 1. Parâmetros e os três modos ───────────────────────────────────────────────────────────────────────
alter table public.agenda_config
  add column if not exists modo_material               text          not null default 'desligado',
  add column if not exists modo_detector               text          not null default 'desligado',
  add column if not exists modo_fornecedor             text          not null default 'desligado',
  add column if not exists oc_viva_dias                smallint      not null default 60,
  add column if not exists remessa_dias                smallint      not null default 30,
  add column if not exists material_inicio_dias        smallint      not null default 14,
  add column if not exists material_pergunta_validade  interval      not null default '7 days',
  add column if not exists nfe_opcoes_max              smallint      not null default 3,
  add column if not exists pix_janela_dias             smallint      not null default 7,
  add column if not exists pix_valor_minimo            numeric(10,2) not null default 50,
  add column if not exists pix_perguntas_semana_max    smallint      not null default 1,
  add column if not exists pix_categorias              text[]        not null
    default '{"Peças e materiais","Compras de mercadorias","Materiais e Insumos Operacionais"}',
  add column if not exists prazo_longo_du              smallint      not null default 10,
  add column if not exists detector_janela_horas       smallint      not null default 48,
  add column if not exists detector_lote_max           smallint      not null default 100,
  add column if not exists detector_precisao_minima    numeric(3,2)  not null default 0.70,
  add column if not exists detector_minimo_julgados    smallint      not null default 5,
  add column if not exists detector_tolerancia_du      smallint      not null default 1,
  add column if not exists detector_modelo_max         smallint      not null default 5,
  add column if not exists fornecedor_janela_inicio    time          not null default '08:00',
  add column if not exists fornecedor_janela_fim       time          not null default '18:00',
  add column if not exists fornecedor_sabado           boolean       not null default false,
  add column if not exists fornecedor_dia_max          smallint      not null default 1,
  add column if not exists fornecedor_semana_max       smallint      not null default 2,
  add column if not exists fornecedor_total_dia_max    smallint      not null default 5,
  add column if not exists fornecedor_conversa_dias    smallint      not null default 90,
  add column if not exists fornecedores_principais_max smallint      not null default 15;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_modo_material_check',               'check (modo_material in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_detector_check',               'check (modo_detector in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_fornecedor_check',             'check (modo_fornecedor in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_oc_viva_dias_check',                'check (oc_viva_dias between 14 and 180)'),
      ('agenda_config_remessa_dias_check',                'check (remessa_dias between 7 and 120)'),
      ('agenda_config_material_inicio_dias_check',        'check (material_inicio_dias between 7 and 28)'),
      ('agenda_config_material_pergunta_validade_check',  'check (material_pergunta_validade between interval ''1 day'' and interval ''14 days'')'),
      ('agenda_config_nfe_opcoes_max_check',              'check (nfe_opcoes_max between 1 and 5)'),
      ('agenda_config_pix_janela_dias_check',             'check (pix_janela_dias between 1 and 30)'),
      ('agenda_config_pix_valor_minimo_check',            'check (pix_valor_minimo between 0 and 1000)'),
      ('agenda_config_pix_perguntas_semana_max_check',    'check (pix_perguntas_semana_max between 0 and 5)'),
      ('agenda_config_pix_categorias_check',              'check (cardinality(pix_categorias) >= 1)'),
      ('agenda_config_prazo_longo_du_check',              'check (prazo_longo_du between 5 and 30)'),
      ('agenda_config_detector_janela_horas_check',       'check (detector_janela_horas between 6 and 96)'),
      ('agenda_config_detector_lote_max_check',           'check (detector_lote_max between 10 and 500)'),
      ('agenda_config_detector_precisao_minima_check',    'check (detector_precisao_minima between 0.5 and 0.95)'),
      ('agenda_config_detector_minimo_julgados_check',    'check (detector_minimo_julgados between 3 and 30)'),
      ('agenda_config_detector_tolerancia_du_check',      'check (detector_tolerancia_du between 0 and 3)'),
      ('agenda_config_detector_modelo_max_check',         'check (detector_modelo_max between 0 and 20)'),
      ('agenda_config_fornecedor_janela_inicio_check',    'check (fornecedor_janela_inicio between time ''07:00'' and time ''10:00'')'),
      ('agenda_config_fornecedor_janela_fim_check',       'check (fornecedor_janela_fim between time ''16:00'' and time ''19:00'')'),
      ('agenda_config_fornecedor_dia_max_check',          'check (fornecedor_dia_max between 1 and 2)'),
      ('agenda_config_fornecedor_semana_max_check',       'check (fornecedor_semana_max between 1 and 5)'),
      ('agenda_config_fornecedor_total_dia_max_check',    'check (fornecedor_total_dia_max between 1 and 20)'),
      ('agenda_config_fornecedor_conversa_dias_check',    'check (fornecedor_conversa_dias between 0 and 365)'),
      ('agenda_config_fornecedores_principais_max_check', 'check (fornecedores_principais_max between 5 and 30)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

-- Como as Fases 2 e 3: a estrutura não muda comportamento. A linha que já existe fica 'desligado' (do add column acima);
-- quem a põe em sombra é a migration de dado 20261027101000, com OK nomeado.
alter table public.agenda_config
  alter column modo_material set default 'sombra',
  alter column modo_detector set default 'sombra',
  alter column modo_fornecedor set default 'sombra';

comment on column public.agenda_config.modo_material is
  'desligado = a agenda não lê nota nem Pix; sombra = grava a remessa e as perguntas (nunca aparecem); ligado = as perguntas de material vão ao fechamento e à carona (com modo_vigia ligado) e a nota importada ligada vira na mão.';
comment on column public.agenda_config.modo_detector is
  'desligado = não lê a conversa do fornecedor; sombra = grava o sinal e o que faria (para medir a precisão); ligado = atualiza a previsão da compra já ligada, com desfaz, e pergunta o resto.';
comment on column public.agenda_config.modo_fornecedor is
  'desligado = nada ao fornecedor; sombra = grava a mensagem que mandaria; ligado = manda a mensagem-modelo dos terços, na janela, com teto.';
comment on column public.agenda_config.oc_viva_dias is 'OC viva: criada há menos destes dias (e sem OS encerrada) abate a falta de catálogo (o "já pedido" de v_oc_itens_a_caminho). Era o "60 dias" escrito na view (Fase 0).';
comment on column public.agenda_config.remessa_dias is 'NF-e do e-mail emitida há mais destes dias não vira remessa.';
comment on column public.agenda_config.material_inicio_dias is '"A OS que começa nas próximas semanas": as perguntas de material (nota, Pix) só falam de OS com início até estes dias corridos.';
comment on column public.agenda_config.material_pergunta_validade is 'A pergunta de material (nota, Pix, previsão do fornecedor) sem resposta vence depois disto.';
comment on column public.agenda_config.nfe_opcoes_max is 'Quantas OS a pergunta "é material de qual serviço?" oferece (mais a opção "nenhum").';
comment on column public.agenda_config.pix_janela_dias is 'O Pix a fornecedor de material dos últimos estes dias pode virar pergunta.';
comment on column public.agenda_config.pix_valor_minimo is 'Pix abaixo deste valor (R$) não vira pergunta.';
comment on column public.agenda_config.pix_perguntas_semana_max is 'Perguntas de Pix por semana ISO, no total (não por OS). 0 = nenhuma.';
comment on column public.agenda_config.pix_categorias is 'As categorias da fila financeira (finance_review_queue.suggested_category) que são compra de material.';
comment on column public.agenda_config.prazo_longo_du is 'Compra com prazo acima destes dias úteis ganha a pergunta ao fornecedor nos terços do prazo.';
comment on column public.agenda_config.detector_janela_horas is 'Quanto da conversa do fornecedor o detector relê a cada passada.';
comment on column public.agenda_config.detector_lote_max is 'Mensagens por passada do detector.';
comment on column public.agenda_config.detector_precisao_minima is 'O detector só liga com pelo menos esta fração de acertos (julgados pelo fato) …';
comment on column public.agenda_config.detector_minimo_julgados is '… em pelo menos estes casos julgados.';
comment on column public.agenda_config.detector_tolerancia_du is 'A previsão do detector está certa se a chegada real (chegou_em) ficou a até estes dias úteis dela, para mais ou para menos (C1 da revisão: a previsão que o dono informou não julga).';
comment on column public.agenda_config.detector_modelo_max is 'Quantas vezes por rodada (15 min) o acompanhar-conversas chama o modelo pago para escolher de qual compra o fornecedor fala; passou disso, a mensagem vai sem o modelo e a pergunta ao dono lista as compras. 0 = nunca (C1 da revisão da Fase 4).';
comment on column public.agenda_config.fornecedor_janela_inicio is 'Mensagem ao fornecedor: a 1ª hora em que sai (seg a sex; sábado só com fornecedor_sabado; nunca domingo).';
comment on column public.agenda_config.fornecedor_janela_fim is 'Mensagem ao fornecedor: nada sai desta hora em diante.';
comment on column public.agenda_config.fornecedor_sabado is 'A mensagem ao fornecedor pode sair no sábado (na mesma janela).';
comment on column public.agenda_config.fornecedor_dia_max is 'Mensagens ao MESMO fornecedor por dia.';
comment on column public.agenda_config.fornecedor_semana_max is 'Mensagens ao MESMO fornecedor por semana ISO.';
comment on column public.agenda_config.fornecedor_total_dia_max is 'Mensagens a fornecedores por dia, somando todos.';
comment on column public.agenda_config.fornecedor_conversa_dias is 'Só pergunta ao fornecedor que conversou com a HBR pelo WhatsApp nestes dias. 0 = sem essa exigência.';
comment on column public.agenda_config.fornecedores_principais_max is 'Quantos fornecedores o foco "fornecedores" mostra (os principais de material).';

-- ── 2. O prazo dito por fornecedor ──────────────────────────────────────────────────────────────────────
alter table public.suppliers
  add column if not exists modalidade          text,
  add column if not exists prazo_dias_uteis    smallint,
  add column if not exists prazo_dias_corridos smallint,
  add column if not exists prazo_fonte         text,
  add column if not exists prazo_informado_em  timestamptz,
  add column if not exists prazo_trecho        text;

-- Por nome: drop if exists + add (a lista de modalidades é a de agenda_config.prazo_classe_du + importacao; o teste B3
-- confere que cada uma, menos importacao, existe lá).
alter table public.suppliers drop constraint if exists suppliers_modalidade_check;
alter table public.suppliers add constraint suppliers_modalidade_check
  check (modalidade is null
         or modalidade in ('balcao', 'entrega_local', 'distribuidor_sc_pr', 'outro_estado', 'marketplace', 'importacao'));
alter table public.suppliers drop constraint if exists suppliers_prazo_coerente;
alter table public.suppliers add constraint suppliers_prazo_coerente
  check ((modalidade is null) = (prazo_fonte is null)
         and (prazo_dias_uteis is null
              or (modalidade is not null and modalidade <> 'importacao' and prazo_dias_uteis between 0 and 60))
         and (prazo_dias_corridos is null
              or (modalidade is not null and modalidade = 'importacao' and prazo_dias_corridos between 1 and 120)));
alter table public.suppliers drop constraint if exists suppliers_prazo_fonte_check;
alter table public.suppliers add constraint suppliers_prazo_fonte_check
  check (prazo_fonte is null or prazo_fonte in ('dono', 'medido'));
alter table public.suppliers drop constraint if exists suppliers_prazo_trecho_check;
alter table public.suppliers add constraint suppliers_prazo_trecho_check
  check (prazo_trecho is null or char_length(prazo_trecho) <= 300);

comment on column public.suppliers.modalidade is
  'Agenda de Produção (Fase 4): como o DONO compra deste fornecedor — balcao, entrega_local, distribuidor_sc_pr, outro_estado, marketplace (as chaves de agenda_config.prazo_classe_du) ou importacao. Nulo = vale o chute pela cidade/UF. Só muda pelo *grava* do dono (agenda_rascunho_fornecedor).';
comment on column public.suppliers.prazo_dias_uteis is 'Agenda de Produção (Fase 4): os dias úteis que o dono disse (não importado). Nulo = o da classe (agenda_config.prazo_classe_du).';
comment on column public.suppliers.prazo_dias_corridos is 'Agenda de Produção (Fase 4): só importado — os dias corridos que o dono disse. Nulo = agenda_config.importacao_dias.';
comment on column public.suppliers.prazo_fonte is 'Agenda de Produção (Fase 4): dono (o que ele disse); Fase 6: medido (a pontualidade). Existe junto da modalidade.';
comment on column public.suppliers.prazo_informado_em is 'Agenda de Produção (Fase 4): quando o prazo foi gravado.';
comment on column public.suppliers.prazo_trecho is 'Agenda de Produção (Fase 4): as palavras do dono sobre o prazo.';

-- ── 3. A linha da OC ligada à linha da OS ───────────────────────────────────────────────────────────────
alter table public.purchase_order_items
  add column if not exists service_order_part_id    uuid references public.service_order_parts(id) on delete set null,
  add column if not exists service_order_service_id uuid references public.service_order_services(id) on delete set null;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.purchase_order_items'::regclass and conname = 'poi_um_vinculo_de_linha') then
    alter table public.purchase_order_items add constraint poi_um_vinculo_de_linha
      check (num_nonnulls(service_order_part_id, service_order_service_id) <= 1);
  end if;
end
$$;

create index if not exists poi_linha_servico on public.purchase_order_items(service_order_service_id)
  where service_order_service_id is not null;
create index if not exists poi_linha_peca on public.purchase_order_items(service_order_part_id)
  where service_order_part_id is not null;

comment on column public.purchase_order_items.service_order_part_id is
  'Agenda de Produção (Fase 4): a peça da OS que esta linha compra (copiada da cotação; na OC pela OS, da linha em falta). Apagar a peça deixa nulo.';
comment on column public.purchase_order_items.service_order_service_id is
  'Agenda de Produção (Fase 4): a linha de serviço/texto livre da OS que esta linha compra. Com ela, a OC cobre a falta daquela linha (P2). Apagar a linha deixa nulo.';

-- ── 4. As tabelas do material (a remessa antes de os_material, que aponta para ela) ─────────────────────

-- (1) A NF-e que chegou por e-mail, no nível da NOTA: a data de despacho e a previsão. NUNCA apagada.
create table if not exists public.material_remessas (
  id                  uuid primary key default gen_random_uuid(),
  nfe_chave           text not null unique check (nfe_chave ~ '^[0-9]{44}$'),
  email_message_id    uuid references public.email_messages(id) on delete set null,
  email_attachment_id uuid references public.email_attachments(id) on delete set null,
  fornecedor_id       uuid references public.suppliers(id) on delete set null,
  emitente            text check (char_length(emitente) <= 120),
  emitente_cnpj       text check (emitente_cnpj is null or emitente_cnpj ~ '^[0-9A-Z]{12}[0-9]{2}$|^[0-9]{11}$'),
  emitente_uf         text check (emitente_uf is null or emitente_uf ~ '^[A-Z]{2}$'),
  emitente_municipio  text check (char_length(emitente_municipio) <= 80),
  numero              text check (char_length(numero) <= 20),
  valor               numeric(14,2),
  emitida_em          date not null,
  saida_em            date,
  despacho_em         date generated always as (coalesce(saida_em, emitida_em)) stored,
  mod_frete           text check (mod_frete is null or mod_frete ~ '^[0-9]$'),
  classe              text,
  prazo_du            smallint,
  previsao_ate        date,
  itens               jsonb not null default '[]'
                        check (jsonb_typeof(itens) = 'array' and jsonb_array_length(itens) <= 40),
  estado              text not null default 'a_caminho' check (estado in ('a_caminho', 'chegou', 'descartada')),
  vinculo             text not null default 'sem_resposta' check (vinculo in ('sem_resposta', 'ligada', 'sem_servico')),
  os_ids              uuid[] not null default '{}',
  respondida_em       timestamptz,
  respondida_por      uuid references public.app_users(id) on delete set null,
  fiscal_note_id      uuid references public.fiscal_notes(id) on delete set null,
  chegou_em           date,
  criada_em           timestamptz not null default now(),
  historico           jsonb not null default '[]'
                        check (jsonb_typeof(historico) = 'array' and jsonb_array_length(historico) <= 20),
  constraint remessa_chegou_tem_data   check ((estado = 'chegou') = (chegou_em is not null)),
  constraint remessa_ligada_tem_os     check ((vinculo = 'ligada') = (cardinality(os_ids) > 0)),
  constraint remessa_resposta_coerente check ((vinculo = 'sem_resposta') = (respondida_em is null))
);

create index if not exists material_remessas_abertas on public.material_remessas(estado, vinculo)
  where vinculo = 'sem_resposta';

comment on table public.material_remessas is
  'Agenda de Produção (Fase 4): a NF-e que chegou por e-mail, no nível da NOTA — o emitente (e o fornecedor pelo CNPJ), a emissão, a saída (dhSaiEnt), o despacho (a saída, senão a emissão), o frete, a classe e o prazo do fornecedor quando gravou, a previsão (despacho + prazo; nula = prazo desconhecido), os itens (até 40) e a resposta do dono (de qual serviço é). O vínculo nota ↔ OS é SEMPRE do dono: sem resposta, nenhuma OS muda. NUNCA apagada; só o estado, o vínculo, a resposta, a nota importada, a chegada, o histórico e o que o cadastro corrigir mudam.';
comment on column public.material_remessas.despacho_em is 'A saída (dhSaiEnt), senão a emissão (dhEmi): o dia de onde conta o prazo (revisão item 16).';
comment on column public.material_remessas.previsao_ate is 'Despacho + o prazo do fornecedor (ou do lugar, sem cadastro). Nula = prazo desconhecido.';
comment on column public.material_remessas.itens is '[{n, descricao, qtd, un}] do XML, até 40.';
comment on column public.material_remessas.os_ids is 'As OS que o dono disse (vinculo ligada).';

-- (2) O que o detector leu na conversa do fornecedor. Uma linha por mensagem e tipo. NUNCA apagada.
create table if not exists public.material_sinais (
  id                  uuid primary key default gen_random_uuid(),
  whatsapp_message_id uuid not null references public.whatsapp_messages(id) on delete cascade,
  fornecedor_id       uuid references public.suppliers(id) on delete set null,
  direcao             text not null check (direcao in ('recebida', 'enviada')),
  ocorreu_em          timestamptz not null,
  dia                 date not null,
  tipo                text not null check (tipo in ('despacho', 'chegada', 'prazo', 'perguntou_chegou', 'atraso')),
  expressao           text check (char_length(expressao) <= 60),
  condicional         boolean not null default false,
  trecho              text not null check (char_length(trecho) between 3 and 300),
  data_de             date,
  data_ate            date,
  candidatos          jsonb not null default '[]' check (jsonb_typeof(candidatos) = 'array'),
  os_material_id      uuid references public.os_material(id) on delete set null,
  service_order_id    uuid references public.service_orders(id) on delete set null,
  casou_por           text check (casou_por in ('unico', 'modelo', 'nenhum')),
  modelo_confianca    numeric(3,2) check (modelo_confianca between 0 and 1),
  modo                text not null check (modo in ('sombra', 'ligado')),
  estado              text not null default 'registrado'
                        check (estado in ('registrado', 'esperando', 'aplicado', 'perguntado', 'descartado')),
  faria               jsonb not null default '{}' check (jsonb_typeof(faria) = 'object'),
  motivo              text check (char_length(motivo) <= 200),
  acao_id             uuid references public.agenda_acoes(id) on delete set null,
  pergunta_id         uuid references public.agenda_perguntas(id) on delete set null,
  julgamento          text check (julgamento in ('certo', 'errado', 'sem_como_saber')),
  julgado_em          timestamptz,
  julgado_por         text check (julgado_por in ('fato', 'dono')),
  criado_em           timestamptz not null default now(),
  unique (whatsapp_message_id, tipo),
  constraint sinal_faixa_coerente   check (data_de is null or data_ate is null or data_de <= data_ate),
  constraint sinal_julgado_coerente check ((julgamento is null) = (julgado_em is null))
);

create index if not exists material_sinais_abertos on public.material_sinais(estado, criado_em)
  where estado in ('registrado', 'esperando');

comment on table public.material_sinais is
  'Agenda de Produção (Fase 4): o que o detector leu na conversa do fornecedor (os dois lados: recebida = o fornecedor, enviada = a HBR) — o tipo (despacho, chegada, prazo, perguntou se chegou, atraso), a expressão dita ("amanhã", "dia 14", "5 dias úteis"; a data sai do banco), as compras candidatas, a escolhida, o que faria (sombra) ou fez (ligado), e o julgamento pelo fato (a precisão do detector). Uma por mensagem e tipo. NUNCA apagada.';
comment on column public.material_sinais.candidatos is '[{n, os, os_material_id, rotulo}]: as compras vivas daquele fornecedor.';
comment on column public.material_sinais.faria is '{acao, data_ate, fonte, texto}: o que o gestor faz (ligado) ou faria (sombra).';

-- (3) Toda mensagem ao fornecedor (mandada ou só registrada em sombra). NUNCA apagada.
create table if not exists public.agenda_fornecedor_mensagens (
  id               uuid primary key default gen_random_uuid(),
  fornecedor_id    uuid not null references public.suppliers(id),
  os_material_id   uuid references public.os_material(id) on delete set null,
  service_order_id uuid references public.service_orders(id) on delete set null,
  tipo             text not null check (tipo in ('confirmar_prazo')),
  terco            smallint not null check (terco in (1, 2)),
  modo             text not null check (modo in ('sombra', 'ligado')),
  texto            text not null check (char_length(texto) between 3 and 600),
  enviar_em        timestamptz not null,
  estado           text not null default 'registrada' check (estado in ('registrada', 'enfileirada', 'recusada')),
  recusa_motivo    text check (recusa_motivo in ('teto', 'janela', 'fim_de_semana', 'domingo', 'sem_telefone', 'opt_out',
                                                 'sem_conversa', 'modo')),
  fila_id          uuid,
  dedupe_key       text not null unique,
  criada_em        timestamptz not null default now(),
  constraint fornecedor_recusa_coerente check ((estado = 'recusada') = (recusa_motivo is not null))
);

create index if not exists agenda_fornecedor_por_envio on public.agenda_fornecedor_mensagens(fornecedor_id, enviar_em desc);

comment on table public.agenda_fornecedor_mensagens is
  'Agenda de Produção (Fase 4): toda mensagem ao fornecedor — só a mensagem-modelo "a entrega continua para dd/mm?" nos terços de um prazo longo —, mandada (ligado) ou só registrada (sombra), recusada com o motivo (teto, janela, fim de semana, domingo, sem telefone, opt-out, sem conversa recente, modo). Nunca leva valor, nome do cliente nem número de OS (a OS fica só no registro). NUNCA apagada; só o estado, a recusa e a fila mudam.';
comment on column public.agenda_fornecedor_mensagens.fila_id is 'whatsapp_send_queue.id quando enfileirada (sem FK: a fila é podada).';
comment on column public.agenda_fornecedor_mensagens.dedupe_key is 'agenda-fornecedor:terco:<os_material>:<n>[:sombra] — a chave da fila. Em sombra termina em ":sombra" (a de verdade não colide com a registrada).';

-- ── 5. os_material: de onde veio a compra, o original da previsão e a nota ──────────────────────────────
alter table public.os_material
  add column if not exists comprado_fonte          text,
  add column if not exists previsao_original_fonte text,
  add column if not exists previsao_original_em    date,
  add column if not exists remessa_id              uuid references public.material_remessas(id) on delete set null;

create index if not exists os_material_remessa on public.os_material(remessa_id) where remessa_id is not null;

-- As linhas que já existem (Fases 1–3 aplicadas antes desta) com o original sem a fonte: a regra do gatilho, antes do
-- CHECK. O dia fica nulo (não se sabe quando a 1ª previsão foi gravada). Rodar de novo não acha nada.
update public.os_material
   set previsao_original_fonte = coalesce(previsao_fonte,
                                          case when fonte in ('dono', 'fornecedor', 'nfe', 'pix') then fonte end, 'oc')
 where previsao_original is not null and previsao_original_fonte is null;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('os_material_comprado_fonte_check',
       'check (comprado_fonte is null or comprado_fonte in (''dono'', ''pix'', ''nfe'', ''oc'', ''fornecedor''))'),
      ('os_material_previsao_original_fonte_check',
       'check (previsao_original_fonte is null or previsao_original_fonte in (''dono'', ''fornecedor'', ''nfe'', ''oc'', ''pix''))'),
      ('os_material_original_coerente',
       'check ((previsao_original is null) = (previsao_original_fonte is null))')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.os_material'::regclass and conname = r.nome) then
      execute format('alter table public.os_material add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.os_material.comprado_fonte is 'Agenda de Produção (Fase 4): de onde veio o "comprado" — dono, pix, nfe, oc ou fornecedor.';
comment on column public.os_material.previsao_original_fonte is 'Agenda de Produção (Fase 4): a fonte da 1ª previsão (a mesma lista de previsao_fonte). Existe junto de previsao_original.';
comment on column public.os_material.previsao_original_em is 'Agenda de Produção (Fase 4): o dia em que a 1ª previsão foi gravada (nulo nas linhas de antes da Fase 4).';
comment on column public.os_material.remessa_id is 'Agenda de Produção (Fase 4): a nota (material_remessas) que o dono ligou a esta linha.';
comment on column public.os_material.previsao_original is
  'A 1ª previsão de chegada da compra (Fase 4: guardada SEMPRE pelo gatilho _os_material_previsao_original, qualquer que seja o caminho). A compra nova, depois de a linha voltar a faltar, começa um original novo e o de antes vai ao histórico.';

-- O original da previsão, em todos os caminhos de escrita. security definer como a spec pede: só mexe em NEW, e o histórico
-- é cortado por _os_material_historico (que é só do service_role).
create or replace function public._os_material_previsao_original()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_entrada jsonb;
  v_ultima  jsonb;
begin
  if tg_op = 'UPDATE' and old.previsao_original is not null then
    if old.situacao = 'falta' and new.situacao in ('comprado', 'a_caminho') then
      -- Compra nova depois de a linha voltar a faltar: o original de antes vai ao histórico (antes da entrada que o
      -- caminho da escrita acrescentou nesta mesma mudança, que continua sendo a última) e vale o que chegar agora.
      v_entrada := jsonb_build_object('em', public._agenda_hoje(), 'de', 'original', 'valor', old.previsao_original,
                                      'fonte', old.previsao_original_fonte);
      if new.historico -> -1 is distinct from old.historico -> -1 and jsonb_array_length(new.historico) > 0 then
        v_ultima := new.historico -> -1;
        new.historico := public._os_material_historico(
                           public._os_material_historico(new.historico - (-1), v_entrada), v_ultima);
      else
        new.historico := public._os_material_historico(new.historico, v_entrada);
      end if;
      new.previsao_original := null;
      new.previsao_original_fonte := null;
      new.previsao_original_em := null;
    else
      -- O original não muda.
      new.previsao_original := old.previsao_original;
      new.previsao_original_fonte := old.previsao_original_fonte;
      new.previsao_original_em := old.previsao_original_em;
    end if;
  end if;

  if new.previsao_original is null and new.previsao_ate is not null then
    new.previsao_original := new.previsao_ate;
    -- A previsão sem fonte é recusada pelo CHECK previsao_tem_fonte da linha: o original não pode ser ele a recusar.
    new.previsao_original_fonte := coalesce(new.previsao_fonte,
                                            case when new.fonte in ('dono', 'fornecedor', 'nfe', 'pix') then new.fonte end, 'oc');
    new.previsao_original_em := public._agenda_hoje();
  elsif new.previsao_original is not null and new.previsao_original_fonte is null then
    -- O original escrito pelo caminho das Fases 1–3, que não conhece a fonte: a da previsão; sem ela, a do fato
    -- informado; sem as duas, 'oc' (a única previsão que o sistema grava sozinho).
    new.previsao_original_fonte := coalesce(new.previsao_fonte,
                                            case when new.fonte in ('dono', 'fornecedor', 'nfe', 'pix') then new.fonte end, 'oc');
    new.previsao_original_em := coalesce(new.previsao_original_em, public._agenda_hoje());
  end if;
  return new;
end;
$function$;

comment on function public._os_material_previsao_original() is
  'Agenda de Produção (Fase 4): gatilho BEFORE INSERT/UPDATE de os_material — a 1ª previsão (previsao_ate) vira previsao_original, com a fonte e o dia (_agenda_hoje), qualquer que seja o caminho; depois disso o original não muda, salvo na compra nova (a linha estava em falta e passa a comprado/a caminho): o de antes vai ao histórico ({em, de: original, valor, fonte}) e vale o próximo.';

drop trigger if exists os_material_previsao_original on public.os_material;
create trigger os_material_previsao_original before insert or update on public.os_material
  for each row execute function public._os_material_previsao_original();

-- ── 6. Os registros não se apagam e só mudam no estado ──────────────────────────────────────────────────
create or replace function public._material_remessas_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  -- despacho_em é coluna gerada: no gatilho BEFORE ela ainda não foi calculada (vem nula em NEW). Ela sai da saída e da
  -- emissão, que não mudam.
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new),
           array['estado', 'vinculo', 'os_ids', 'respondida_em', 'respondida_por', 'fiscal_note_id', 'chegou_em', 'historico',
                 'fornecedor_id', 'classe', 'prazo_du', 'previsao_ate', 'despacho_em'],
           array['email_message_id', 'email_attachment_id', 'fornecedor_id', 'respondida_por', 'fiscal_note_id']) then
    raise exception 'A nota registrada não muda: só o estado, o vínculo, a resposta, a chegada e o prazo.';
  end if;
  return new;
end;
$function$;

comment on function public._material_remessas_so_muda() is
  'Agenda de Produção (Fase 4): gatilho BEFORE UPDATE de material_remessas — só estado, vinculo, os_ids, respondida_*, fiscal_note_id, chegou_em, historico, fornecedor_id (cadastro novo casado depois), classe, prazo_du e previsao_ate mudam; a chave, a nota e o XML ficam como foram.';

create or replace function public._material_sinais_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new),
           array['estado', 'faria', 'motivo', 'acao_id', 'pergunta_id', 'julgamento', 'julgado_em', 'julgado_por',
                 'os_material_id', 'service_order_id', 'casou_por', 'modelo_confianca', 'data_de', 'data_ate'],
           array['fornecedor_id', 'os_material_id', 'service_order_id', 'acao_id', 'pergunta_id']) then
    raise exception 'O sinal registrado não muda: só o estado, o que faria, o vínculo e o julgamento.';
  end if;
  return new;
end;
$function$;

comment on function public._material_sinais_so_muda() is
  'Agenda de Produção (Fase 4): gatilho BEFORE UPDATE de material_sinais — só estado, faria, motivo, acao_id, pergunta_id, julgamento, julgado_*, os_material_id, service_order_id, casou_por, modelo_confianca, data_de e data_ate mudam; a mensagem, o trecho e a expressão ficam como foram.';

create or replace function public._agenda_fornecedor_mensagens_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new), array['estado', 'recusa_motivo', 'fila_id'],
                                 array['os_material_id', 'service_order_id']) then
    raise exception 'A mensagem ao fornecedor registrada não muda: só o estado, a recusa e a fila.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_fornecedor_mensagens_so_muda() is
  'Agenda de Produção (Fase 4): gatilho BEFORE UPDATE de agenda_fornecedor_mensagens — só estado, recusa_motivo e fila_id mudam; o texto, o fornecedor, o terço e o modo ficam como foram.';

drop trigger if exists material_remessas_nao_apaga on public.material_remessas;
create trigger material_remessas_nao_apaga before delete on public.material_remessas
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists material_remessas_so_muda on public.material_remessas;
create trigger material_remessas_so_muda before update on public.material_remessas
  for each row execute function public._material_remessas_so_muda();

drop trigger if exists material_sinais_nao_apaga on public.material_sinais;
create trigger material_sinais_nao_apaga before delete on public.material_sinais
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists material_sinais_so_muda on public.material_sinais;
create trigger material_sinais_so_muda before update on public.material_sinais
  for each row execute function public._material_sinais_so_muda();

drop trigger if exists agenda_fornecedor_mensagens_nao_apaga on public.agenda_fornecedor_mensagens;
create trigger agenda_fornecedor_mensagens_nao_apaga before delete on public.agenda_fornecedor_mensagens
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_fornecedor_mensagens_so_muda on public.agenda_fornecedor_mensagens;
create trigger agenda_fornecedor_mensagens_so_muda before update on public.agenda_fornecedor_mensagens
  for each row execute function public._agenda_fornecedor_mensagens_so_muda();

-- ── 7. As listas fechadas ampliadas ─────────────────────────────────────────────────────────────────────
-- Perguntas: os 17 tipos da Fase 3 + os 5 do material. A coluna gerada critica NÃO muda (nenhum tipo novo é crítico:
-- são fatos que só o dono sabe, não decisões de agenda).
alter table public.agenda_perguntas drop constraint if exists agenda_perguntas_tipo_check;
alter table public.agenda_perguntas add constraint agenda_perguntas_tipo_check
  check (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono',
                  'conferencia','chegou','parada','estouro','duracao','material_conferir','padrao_do_dono',
                  'diaria','diaria_ligar','equipe_resposta','concluir','entrega',
                  'nfe_vincular','pix_material','previsao_fornecedor','fornecedor_cadastro','fornecedores_prazo'));

comment on column public.agenda_perguntas.chave is
  'chegou:<os_material>:<previsao_ate>, conferencia:<dia>, nao_cabe:<os>:<versao>… — a mesma pergunta não abre duas vezes. Fase 4: fornecedor_cadastro:<fornecedor> e fornecedores_prazo (uma só), que o *grava* do prazo do fornecedor resolve.';

alter table public.agenda_acoes drop constraint if exists agenda_acoes_tipo_check;
alter table public.agenda_acoes add constraint agenda_acoes_tipo_check
  check (tipo in ('publicar','criar','mover','cancelar','fixar','promover_reserva','soltar_reserva','status','resultado',
                  'desfazer','diaria','concluir','entregar','equipe','material','fornecedor'));
alter table public.agenda_acoes drop constraint if exists agenda_acoes_origem_check;
alter table public.agenda_acoes add constraint agenda_acoes_origem_check
  check (origem in ('motor','vigia','conferencia','dono','assistente','tela','aprovacao','sistema','equipe',
                    'fornecedor','nota'));

alter table public.agenda_rascunho drop constraint if exists agenda_rascunho_tipo_check;
alter table public.agenda_rascunho add constraint agenda_rascunho_tipo_check
  check (tipo in ('planejar', 'material', 'disponibilidade', 'marcar', 'aplicar', 'desfazer', 'andamento', 'fornecedor'));

comment on table public.agenda_rascunho is
  'Agenda de Produção: o que o dono disse na conversa e ainda não mandou gravar. Uma linha aberta por chave (planejar:<os>, material:<linha>, disp:<pessoa>:<quando>:<turno>; Fase 2: marcar:<os>, aplicar:<proposta>, decisao:<pergunta>, desfazer:<acao>, andamento:<os>:<dia>:<quem>; Fase 4: fornecedor:<fornecedor>); a correção substitui. Só o *grava* do dono (agenda_rascunho_gravar) transforma em fato.';

-- A rotina do material (P5: agenda_material_vigiar) grava as rodadas na mesma tabela. A agenda_saude já filtra
-- rotina = 'vigia' no bloco da vigia.
alter table public.agenda_vigia_rodadas drop constraint if exists agenda_vigia_rodadas_rotina_check;
alter table public.agenda_vigia_rodadas add constraint agenda_vigia_rodadas_rotina_check
  check (rotina in ('vigia', 'rotina', 'material'));

comment on column public.agenda_vigia_rodadas.rotina is
  'Agenda de Produção (Fase 3): vigia (o tique da Fase 2) ou rotina (a rotina da equipe e da diária); Fase 4: material (a nota, o Pix, o detector e a mensagem ao fornecedor). As rodadas de antes são da vigia.';

-- ── 8. A view das OCs vivas: o prazo em agenda_config e o vínculo de linha (corpo de 20261024150100:61-83) ──
create or replace view public.v_oc_itens_a_caminho with (security_invoker = on) as
select poi.id as purchase_order_item_id,
       poi.purchase_order_id,
       po.po_number,
       po.status as po_status,
       po.service_order_id,
       po.created_at as po_criada_em,
       po.expected_date,
       poi.product_id,
       poi.description,
       poi.quantity,
       poi.received_qty,
       poi.unit_cost,
       greatest(poi.quantity - coalesce(poi.received_qty, 0), 0) as pendente,
       -- Abate a falta de catálogo (o "já pedido")? Só OC viva: recente e sem OS encerrada. NÃO filtra a
       -- view: o "a caminho" de texto livre da própria OS vale com qualquer idade (item 1 do cabeçalho de 150100).
       -- Fase 4: o prazo da OC viva é agenda_config.oc_viva_dias (era o "60 dias" daqui). Sem a linha de config o
       -- resultado é nulo e a OC não abate a falta: o lado seguro (a falta aparece).
       (po.created_at >= now() - make_interval(days => (select c.oc_viva_dias from public.agenda_config c where c.id))
        and (po.service_order_id is null
             or coalesce(so.status not in ('completed', 'invoiced', 'cancelled'), false))) as conta_como_ja_pedido,
       -- Fase 4: a linha da OS que esta linha da OC compra (P2: a OC ligada cobre a falta da linha de texto livre).
       poi.service_order_part_id,
       poi.service_order_service_id
  from public.purchase_order_items poi
  join public.purchase_orders po on po.id = poi.purchase_order_id
  left join public.service_orders so on so.id = po.service_order_id
 where po.status in ('draft', 'sent', 'partial');

comment on view public.v_oc_itens_a_caminho is
  'Itens de OC que ainda vao entregar: OC draft/sent/partial, de qualquer idade. conta_como_ja_pedido = OC criada ha menos de agenda_config.oc_viva_dias (Fase 4; era 60 dias fixo), sem OS ou com a OS viva (fora de completed/invoiced/cancelled): so essas abatem a falta de catalogo (o "ja pedido"). O "a caminho" de texto livre da propria OS nao corta idade. service_order_part_id/service_order_service_id (Fase 4): a linha da OS que a linha da OC compra. Fonte unica de get_os_purchase_needs e de src/hooks/use-purchase-needs.ts. pendente = quantidade - recebido. security_invoker: a RLS de compras (admin/financeiro) e a de agenda_config valem para quem le.';

-- authenticated sai junto e volta só com select: o privilégio padrão do Supabase daria ALL a ele.
revoke all on public.v_oc_itens_a_caminho from public, anon, authenticated;
grant select on public.v_oc_itens_a_caminho to authenticated, service_role;

-- ── 9. Portas: RLS, só leitura, escrita só pelas RPCs ───────────────────────────────────────────────────
alter table public.material_remessas           enable row level security;
alter table public.material_sinais             enable row level security;
alter table public.agenda_fornecedor_mensagens enable row level security;

drop policy if exists material_remessas_leitura on public.material_remessas;
create policy material_remessas_leitura on public.material_remessas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists material_sinais_leitura on public.material_sinais;
create policy material_sinais_leitura on public.material_sinais
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists agenda_fornecedor_mensagens_leitura on public.agenda_fornecedor_mensagens;
create policy agenda_fornecedor_mensagens_leitura on public.agenda_fornecedor_mensagens
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.material_remessas, public.material_sinais, public.agenda_fornecedor_mensagens
  from public, anon, authenticated;
grant select on table public.material_remessas, public.material_sinais, public.agenda_fornecedor_mensagens to authenticated;
grant all on table public.material_remessas, public.material_sinais, public.agenda_fornecedor_mensagens to service_role;

-- Funções de gatilho: sem grant a ninguém.
revoke all on function public._os_material_previsao_original(), public._material_remessas_so_muda(),
  public._material_sinais_so_muda(), public._agenda_fornecedor_mensagens_so_muda()
  from public, anon, authenticated;
