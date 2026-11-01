-- Agenda de Produção, Fase 7, etapa 7c ("quem sabe fazer o quê"), pacote P8: as tarefas do dia (AG7-10) — o gestor DELEGA o que cada
-- pessoa faz no dia (as ETAPAS da OS, tiradas do roteiro ou das linhas do orçamento) e COBRA o feito × pendente, para a OS sair completa e
-- no prazo. Sem mensagem nova a ninguém: a lista vai dentro da ficha das 19:30 e do "como foi" das 17:00 de quem já os recebe; a quem não
-- recebe pelo WhatsApp (o Alex, sem telefone), a lista e o que conferir vão ao dono na linha de etapas do fechamento.
-- Spec: scratchpad agenda-pesquisa/spec-fase7c.md (§R5.2, §R5.4, §R5.5 item 7, §R5.7-8, §R5.10-6, -10, -11 e -13, e o §16 inteiro);
-- nomes: fase7-registro.md §1 (7c P8); respostas do dono: fase7-padroes.md (AG7-10 "cobrar e repassar os serviços corretos para cada
-- pessoal"; AG7-10a a ordem por fase "está certo"; AG7-10b sem escolha → 'tudo'; AG7-10c "o responsável da OS"; AG7-10d "não concluir e me
-- perguntar"; AG7-10e "estão bons"; AG7-01 ligar direto; conflito 7: tarefas_pendente_alerta aceita 1).
-- Depende das Fases 1 a 6, do lote de 30/10, da 7a inteira (_agenda_ampliar_lista, _agenda_regex_valido, mo_fora_regex,
-- _agenda_nome_do_servico, agenda_meios_da_os, _agenda_equipe_tem_telefone), da 7b inteira e da 7c P1 a P6 (20261102100000 .. 100500:
-- agenda_habilidades, os_exigencias, _agenda_atende, _agenda_lider_da_os; a conversa do P4; a linha (n) do P5).
--
-- ═══ DDL — OK NOMEADO ═══ (13 colunas novas em agenda_config — 1 interruptor e 12 parâmetros — e o DEFAULT do interruptor; 2 colunas
-- novas em os_planejamento, nulas; 2 tabelas novas (os_tarefas, os_tarefas_dia) com 4 índices, 4 gatilhos e a RLS de leitura; 4 listas
-- fechadas ampliadas; 10 CHECKs novos por nome em agenda_config (e 6 nas tabelas novas); 22 funções novas, 2 de gatilho e 9
-- recriadas; o grant de _agenda_equipe_tem_telefone; nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7cp8/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (conferida a cada montagem: o
-- montador para se outra migration anterior a esta a definir depois da origem) — _agenda_modo_da_pergunta de
-- 20261102100000_agenda_fase7c_base.sql; agenda_equipe_ficha e _agenda_rotina_conclusao de 20261026100300_agenda_fase3_equipe_diarias.sql;
-- agenda_resposta_da_equipe de 20261101100800_agenda_fase77b_correcao.sql; _agenda_ver_os de 20261024160500_agenda_fase1_leituras.sql;
-- agenda_dia_da_pessoa de 20261025100500_agenda_fase2_leituras.sql; _agenda_rascunho_frase e agenda_rascunho_gravar de
-- 20261102100300_agenda_fase7c_conversa.sql; _agenda_linhas_do_fechamento de 20261102100400_agenda_fase7c_rodada.sql (o R5.4 diz o mesmo)
-- —, e as mudanças entram SÓ como inserções: blocos "-- FASE 7c: (7c P8 …) … -- FASE 7c: fim" antes de uma linha que aparece uma vez no
-- corpo e, dentro de um bloco "-- FASE 7b:" (a linha (n) do fechamento), a marca de dentro "-- (7c P8 …) … -- (7c: fim)" (R5.4 item 2).
-- Nenhuma linha de antes é trocada. Tirados os blocos e as marcas do P8, cada corpo é o da origem, byte a byte (o montador e o T18 de
-- supabase/tests/agenda_fase7c_tarefas.sql conferem). O marcador abre com "-- FASE 7c:" (não "-- FASE 7c P8:", o R5.4 item 2) para os
-- tiradores dos testes de cópia de antes, que casam "-- FASE 7c:" e "-- (7c ", continuarem valendo (o recado do P4 e do P5).
--
-- POR QUE: o dono pediu (AG7-10) que a agenda ajude "a cobrar e repassar os serviços corretos para cada pessoal, a fim de garantir que o
-- serviço seja entregue com tudo feito e dentro do prazo". Até aqui a agenda dizia QUEM vai e QUANDO, nunca O QUE cada um faz no dia, e o
-- "como foi" das 17:00 só perguntava se o turno foi cumprido. O que ficava faltando de um dia não voltava sozinho no seguinte, e o técnico
-- podia "terminar" a OS com etapa faltando.
--
-- O QUE MUDA (tudo atrás de modo_tarefas, que nasce desligado; a migration de dado 20261102100600 o põe em sombra):
--   1. As etapas da OS (os_tarefas): do roteiro, quando a OS tem (cada bloco linha:<sos> é uma etapa; o fechamento é a etapa final; a
--      abertura não), senão das linhas de serviço do orçamento (a régua da mão de obra: sem o material de texto livre, o deslocamento e a
--      logística) mais a etapa final pelos blocos de fechamento de seguranca_da_via. O texto é o nome da linha, limpo (_agenda_tarefa_texto:
--      "SERVIÇO DE PASSAGEM E CRIMPAGEM DE CABOS DE BATERIA" → "Passagem e crimpagem de cabos de bateria"); a ordem é por fase (diagnosticar
--      → desmontar → executar → configurar → testar → entregar, tarefas_fases); o peso é o do orçamento (as etapas somam a duração do plano).
--      A etapa nova do escopo (linha lançada depois) entra no fim, antes de testar e entregar, com uma ação ao dono.
--   2. O plano do dia (os_tarefas_dia): em cada meio-dia marcado da OS cabe até um meio-dia de trabalho; a pendente volta primeiro, depois a
--      começada, depois o resto; a etapa de risco (o que a OS pede pela 7c) só vai a meio-dia cuja equipe atende (_agenda_atende): o
--      ajudante nunca fica sozinho nela. Congela antes da ficha das 19:30 (o de amanhã) e no 1º tique do dia (o de hoje).
--   3. À equipe (só com modo_tarefas ligado): a ficha troca o "Serviço: …" por "O que fazer: 1) …; 2) …" e, no último dia, "É o último dia
--      no barco do Lenine: tem que ficar tudo pronto."; o "como foi" de quem responde ganha a lista do que devia ficar pronto; a resposta
--      "ok, faltou a 2" deixa a etapa pendente (o turno vira parcial, motivo estimativa: o PPC, a duração e o replano fazem o resto).
--   4. Ao dono: a linha (o) "Etapas" do fechamento a quem não recebe pelo WhatsApp (sem números; perda 75 só na véspera do último dia de uma
--      OS ou com pendente dita); a ação tarefa (pendente 2 dias); as perguntas tarefa:prazo e tarefa:quem na linha (n); a linha "Etapas" da
--      OS (agenda_ver com a OS); o que cada um faz no dia (agenda_dia_da_pessoa); a conclusão pela palavra do técnico com etapa pendente dita
--      vira a pergunta concluir; o rascunho etapa (a ferramenta servico_etapa) e o *grava*.
--   5. Sem a palavra de ninguém, o plano segue: a etapa que termina e fica sem resultado depois de tarefas_sem_registro_du dia útil vira
--      sem_registro e conta como feita para o plano — não volta como pendente, não cria "não cabe" e não segura a conclusão (R5.2-3).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7c_tarefas.sql; registradas em notas-fase77c.md, P8):
--   · as leituras com porta (os_tarefas_fonte, os_tarefas_da_os, agenda_tarefas_medidas e _agenda_tarefas_da_pessoa) são DEFINER com a
--     porta explícita (com login, só admin/financeiro, senão 42501; sem login, só o service_role) e grant a authenticated e service_role:
--     elas leem as peças sem grant (o planejar, _agenda_atende, _agenda_lider_da_os), e agenda_dia_da_pessoa e _agenda_linhas_do_fechamento
--     (invoker, lidas pelo painel) chamam _agenda_tarefas_da_pessoa — o molde do P5 (agenda_habilidade_medidas) e do P6;
--   · _agenda_tarefas_lista_texto (IMMUTABLE) tem grant a authenticated e service_role (as duas leituras invoker a chamam) e ganha
--     p_numeros (a linha (o) não numera, R5.10-10); _agenda_tarefa_texto ganha p_max (o tarefas_texto_max: IMMUTABLE não lê a config);
--   · o validador do CHECK de tarefas_fases é a função nova _agenda_tarefas_fases_ok (CHECK não aceita subconsulta: o molde do
--     _agenda_habilidade_config_ok do P1); tarefas_pendente_alerta aceita 1 (CHECK 1..5, padrão 2: o conflito 7 de fase7-padroes.md);
--   · a RPC agenda_rascunho_etapa tem grant a authenticated e service_role (o painel; a spec dizia só service_role: o desvio 1 do P4) e não
--     anota com modo_tarefas desligado (sem etapas não há o que casar; "desligado = nenhuma linha gravada");
--   · o "tudo" que vale como o OK da diária (tarefas_resposta_vale_dia) dá os turnos do plano à leitura gravada, sem virar o tipo ok: o
--     "fiz tudo" é sobre hoje, não confirma a ficha de amanhã que o "como foi" levava.
--
-- O QUE NÃO MUDA: com modo_tarefas desligado, nada roda e nenhuma linha é gravada; as 9 recriadas devolvem o de antes, byte a byte. Em
-- sombra, os textos à equipe, a leitura da resposta, a diária, a conclusão e o que o dono lê (as linhas ligado do fechamento) são os de
-- antes; só as tabelas novas, a linha (o) e as perguntas de modo sombra e as ações de teste existem. A diária, o PPC, o motor, o reestimar
-- do 7a e a conferência do dono não mudam de regra: o pendente chega a eles pelo parcial que já existe. O roteiro só é lido (a chave
-- roteiro_execucao_visivel não muda).
--
-- ORDEM DE LIGAR (spec §16.10, R5.5): depois de 20261102100000 .. 100500 (P1 a P6); antes de 20261102100580 (a correção da revisão, se
-- houver) e do dado 20261102100600 (que põe também modo_tarefas em sombra). O 7d P8 recria agenda_equipe_ficha copiando DESTA; o 7f P5,
-- agenda_resposta_da_equipe; quem recriar _agenda_modo_da_pergunta, _agenda_linhas_do_fechamento, _agenda_rascunho_frase ou
-- agenda_rascunho_gravar copia DESTA (a cadeia do fase7-registro §2).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7c_tarefas.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261102100550
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261102100550_agenda_fase7c_tarefas.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261102100550', 'agenda_fase7c_tarefas');"
--
-- DESFAZER: update agenda_config set modo_tarefas = 'desligado' (na hora: nada mais roda). Estrutura: recriar as 9 com o corpo das
--   origens acima (em ordem) e
--   drop function if exists public.agenda_tarefas_rodar(date, timestamptz), public.agenda_rascunho_etapa(uuid, text, text, text, text,
--     text, text[], text, date), …; as tabelas e as colunas nunca se apagam (o registro da agenda não se apaga).
--
-- IDEMPOTENTE: add column if not exists, create table/index if not exists, os CHECKs por nome (só se não existem), create or replace
-- function, drop trigger if exists + create trigger, drop policy if exists + create policy, revoke/grant, comment, e o ampliador de listas
-- (não toca a tabela quando não há o que somar).

-- ── 1. agenda_config: o interruptor e os parâmetros ──────────────────────────────────────────────────────────────────────
alter table public.agenda_config
  -- a linha fica 'desligado' até a migration de dado 20261102100600 (o molde da 7a, da 7b e da 7c P1); o DEFAULT passa a 'sombra' abaixo
  add column if not exists modo_tarefas                  text         not null default 'desligado',  -- AG7-10, AG7-01 (ligar direto)
  add column if not exists tarefas_linhas_max            smallint     not null default 5,            -- AG7-10 (no máximo 5 linhas na ficha)
  add column if not exists tarefas_texto_max             smallint     not null default 60,           -- desenho (cada linha)
  add column if not exists tarefas_fases                 jsonb        not null default $j$[
    ["testar", 5, "(\\mtest|comissionament|\\mvalidac)"],
    ["entregar", 6, "(\\mentrega\\M|documentac|\\morganizac)"],
    ["configurar", 4, "(\\mconfigur|parametriz|\\mprogramac)"],
    ["desmontar", 2, "(\\mdesmont|\\mremoc|\\mretirad|\\mremov|\\mretirar|\\mdesinstal)"],
    ["diagnosticar", 1, "(\\mdiagnos|\\minspec|\\mvistori|\\mlevantament|\\mavaliac|\\mplanejament)"]
  ]$j$,                                                                                                -- AG7-10a (a ordem do serviço); o resto é executar (3)
  add column if not exists tarefas_horas_min             numeric(4,2) not null default 1.00,         -- desenho (o peso mínimo de uma etapa)
  add column if not exists tarefas_pendente_meios        numeric(3,2) not null default 0.50,         -- desenho (quanto a etapa pendente ainda pede)
  add column if not exists tarefas_pendente_alerta       smallint     not null default 2,            -- AG7-10 (pendente 2 dias vai ao dono; conflito 7)
  add column if not exists tarefas_sem_registro_du       smallint     not null default 1,            -- desenho (R5.2-3: depois disso, segue o plano)
  add column if not exists tarefas_hora                  time         not null default '16:20',      -- desenho (o passo diário: as exceções e o "Em teste")
  add column if not exists tarefas_resposta_vale_dia     text         not null default 'tudo',       -- AG7-10b (a resposta só das etapas e a diária)
  add column if not exists tarefas_concluir_sem_pendente boolean      not null default true,         -- AG7-10d ("não concluir e me perguntar")
  add column if not exists tarefas_cobrar_vespera        boolean      not null default true;         -- AG7-10 (a cobrança no último dia, dentro da ficha)
alter table public.agenda_config alter column modo_tarefas set default 'sombra';

comment on column public.agenda_config.modo_tarefas is
  'Agenda de Produção (Fase 7c, P8; AG7-10, AG7-01): as etapas do dia (o que cada um faz e o feito × pendente). desligado = nada roda; sombra = as etapas e o plano do dia existem como medida, a equipe recebe os textos de antes e o dono vê "Em teste" (no detalhe); ligado = a lista na ficha e no "como foi", a leitura da resposta, as exceções ao dono e a conclusão segura. A linha nasce desligado; o dado 20261102100600 põe sombra; ligar com o OK nomeado "mandar o que fazer à equipe".';
comment on column public.agenda_config.tarefas_linhas_max is 'Agenda de Produção (Fase 7c, P8; AG7-10): quantas etapas a ficha lista, no máximo ("; e mais N").';
comment on column public.agenda_config.tarefas_texto_max is 'Agenda de Produção (Fase 7c, P8): o tamanho do texto de cada etapa (_agenda_tarefa_texto corta no travessão, nos dois pontos ou na última palavra que cabe, com "…").';
comment on column public.agenda_config.tarefas_fases is
  'Agenda de Produção (Fase 7c, P8; AG7-10a): a ordem do serviço — [fase, número, regex] avaliadas na ordem do array sobre o nome do serviço (_agenda_nome_do_servico); vale a 1ª que casa; o resto é executar (3); a etapa final é sempre entregar (6). Fases: diagnosticar 1, desmontar 2, configurar 4, testar 5, entregar 6 (as regex conferidas por _agenda_regex_valido).';
comment on column public.agenda_config.tarefas_horas_min is 'Agenda de Produção (Fase 7c, P8): o peso mínimo de uma etapa, em horas (a linha de R$ 0 e a etapa do dono pesam isto).';
comment on column public.agenda_config.tarefas_pendente_meios is 'Agenda de Produção (Fase 7c, P8): quanto a etapa pendente (alguém disse que faltou) ainda pede, em meios-dias; ela volta primeiro no próximo meio-dia da OS.';
comment on column public.agenda_config.tarefas_pendente_alerta is 'Agenda de Produção (Fase 7c, P8; AG7-10, conflito 7 de AG7-26): em quantos dias diferentes pendente a etapa vira a ação tarefa ao dono (1 a 5; padrão 2).';
comment on column public.agenda_config.tarefas_sem_registro_du is 'Agenda de Produção (Fase 7c, P8; R5.2-3): depois de quantos dias úteis sem resultado a etapa que terminava vira sem_registro (conta como feita para o plano; "sem confirmação" nas leituras).';
comment on column public.agenda_config.tarefas_hora is 'Agenda de Produção (Fase 7c, P8): a hora do passo diário da rodada das etapas (as exceções de todas as OS e o "Em teste"), no tique das 16:30.';
comment on column public.agenda_config.tarefas_resposta_vale_dia is
  'Agenda de Produção (Fase 7c, P8; AG7-10b): a resposta só das etapas ao "como foi" (sem turno nem OK) e a diária — nunca (só a gramática de antes), tudo (padrão: "tudo"/"fiz tudo" valem como o OK, os turnos do plano) ou sempre (toda resposta de etapa entendida vale os turnos do plano).';
comment on column public.agenda_config.tarefas_concluir_sem_pendente is 'Agenda de Produção (Fase 7c, P8; AG7-10d): com etapa pendente dita, o "terminei" do técnico não conclui a OS: vira a pergunta concluir (o *concluiu* do dono conclui como hoje).';
comment on column public.agenda_config.tarefas_cobrar_vespera is 'Agenda de Produção (Fase 7c, P8; AG7-10): a cobrança "É o último dia …: tem que ficar tudo pronto." dentro da ficha de quem responde pela OS no último dia e no dia do prazo (nunca mensagem a mais).';

-- O validador do CHECK de tarefas_fases: um array não vazio de [fase, número, regex], a fase e o número de uma lista fechada (sem executar,
-- que é o resto), a regex que compila (_agenda_regex_valido). CHECK não aceita subconsulta: o molde de _agenda_habilidade_config_ok (7c P1).
create or replace function public._agenda_tarefas_fases_ok(p_fases jsonb)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_typeof(p_fases) = 'array' and jsonb_array_length(p_fases) > 0
           and not exists (
             select 1 from jsonb_array_elements(p_fases) e
              where not (jsonb_typeof(e) = 'array' and jsonb_array_length(e) = 3
                         and jsonb_typeof(e -> 0) = 'string' and jsonb_typeof(e -> 1) = 'number' and jsonb_typeof(e -> 2) = 'string'
                         and (e ->> 0, e ->> 1) in (('diagnosticar', '1'), ('desmontar', '2'), ('configurar', '4'), ('testar', '5'),
                                                    ('entregar', '6'))
                         and public._agenda_regex_valido(e ->> 2))), false);
$function$;

comment on function public._agenda_tarefas_fases_ok(jsonb) is
  'Agenda de Produção (Fase 7c, P8): o validador do CHECK de agenda_config.tarefas_fases — array não vazio de [fase, número, regex] com a fase e o número em diagnosticar 1, desmontar 2, configurar 4, testar 5, entregar 6 (executar 3 é o resto, nunca dito) e a regex que compila. IMMUTABLE; authenticated e service_role (o CHECK).';

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_modo_tarefas_check',              'check (modo_tarefas in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_tarefas_linhas_max_check',        'check (tarefas_linhas_max between 1 and 5)'),
      ('agenda_config_tarefas_texto_max_check',         'check (tarefas_texto_max between 30 and 80)'),
      ('agenda_config_tarefas_fases_check',             'check (public._agenda_tarefas_fases_ok(tarefas_fases))'),
      ('agenda_config_tarefas_horas_min_check',         'check (tarefas_horas_min between 0.25 and 8)'),
      ('agenda_config_tarefas_pendente_meios_check',    'check (tarefas_pendente_meios between 0.25 and 2)'),
      ('agenda_config_tarefas_pendente_alerta_check',   'check (tarefas_pendente_alerta between 1 and 5)'),
      ('agenda_config_tarefas_sem_registro_du_check',   'check (tarefas_sem_registro_du between 0 and 5)'),
      ('agenda_config_tarefas_hora_check',
       'check (tarefas_hora >= time ''12:00'' and tarefas_hora <= equipe_hora_como_foi)'),
      ('agenda_config_tarefas_resposta_vale_dia_check', 'check (tarefas_resposta_vale_dia in (''nunca'', ''tudo'', ''sempre''))')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

-- ── 2. os_planejamento: a assinatura da última sincronização ─────────────────────────────────────────────────────────────
alter table public.os_planejamento
  add column if not exists tarefas_assinatura       text check (char_length(tarefas_assinatura) = 32),  -- md5 da fonte da última sincronização
  add column if not exists tarefas_sincronizadas_em timestamptz;

comment on column public.os_planejamento.tarefas_assinatura is
  'Agenda de Produção (Fase 7c, P8): o md5 das etapas que a OS tinha pela base (os_tarefas_fonte, sem a máscara) na última sincronização: a mesma assinatura e a mesma máscara = nada a refazer. Só _agenda_tarefas_sincronizar escreve.';
comment on column public.os_planejamento.tarefas_sincronizadas_em is 'Agenda de Produção (Fase 7c, P8): quando as etapas da OS foram sincronizadas pela última vez.';

-- ── 3. As tabelas: as etapas da OS e o plano do dia ──────────────────────────────────────────────────────────────────────
create table if not exists public.os_tarefas (
  id               uuid primary key default gen_random_uuid(),
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  chave            text not null check (char_length(chave) between 3 and 120),  -- linha:<sos> · linha:<sos>:<k> · entrega · dono:<uuid>
  origem           text not null check (origem in ('roteiro', 'orcamento', 'seguranca', 'dono', 'ia')),
  service_order_service_id uuid references public.service_order_services(id) on delete set null,
  pai_id           uuid references public.os_tarefas(id) on delete set null,     -- a parte aponta a etapa dividida
  texto            text not null check (char_length(texto) between 3 and 80),
  fase             smallint not null check (fase between 1 and 6),
  ordem            numeric(8,3) not null,
  horas            numeric(6,2) not null check (horas > 0),
  exige            smallint not null default 0 check (exige between 0 and 15),   -- os bits da 7c (1 energizado, 2 comissionar, 4 teto, 8 diagnóstico)
  passos           uuid[] not null default '{}',                                -- os service_order_steps do bloco (com roteiro)
  estado           text not null check (estado in ('viva', 'feita', 'nao_se_aplica', 'saiu', 'substituida')),
  feita_em         timestamptz,
  feita_via        text check (feita_via in ('equipe', 'dono', 'conferencia', 'roteiro')),
  pendente_vezes   smallint not null default 0 check (pendente_vezes >= 0),
  pendente_desde   date,
  pendente_ultimo  date,
  nova_no_escopo   boolean not null default false,
  trecho           text check (char_length(trecho) <= 500),
  criada_em        timestamptz not null,
  criada_por       uuid references public.app_users(id) on delete set null,
  mudou_em         timestamptz not null,
  constraint os_tarefas_feita_coerente    check ((estado = 'feita') = (feita_em is not null and feita_via is not null)),
  constraint os_tarefas_dono_tem_trecho   check (origem not in ('dono', 'ia') or trecho is not null),
  constraint os_tarefas_pendente_coerente check ((pendente_vezes = 0) = (pendente_desde is null and pendente_ultimo is null))
);
create unique index if not exists os_tarefas_viva on public.os_tarefas(service_order_id, chave) where estado in ('viva', 'feita');
create index if not exists os_tarefas_da_os on public.os_tarefas(service_order_id, ordem) where estado = 'viva';

comment on table public.os_tarefas is
  'Agenda de Produção (Fase 7c, P8; AG7-10): as etapas de uma OS — do roteiro (cada bloco linha:<sos>; o fechamento = a etapa final entrega), das linhas de serviço do orçamento (sem material de texto livre, deslocamento e logística) mais a etapa final pelos blocos de fechamento de seguranca_da_via, das palavras do dono (dono:<uuid>) ou da divisão de uma etapa que o dono pediu (<chave>:<k>, origem ia). Peso em horas pelo orçamento (as etapas somam a duração do plano); ordem pela fase (tarefas_fases) e, dentro dela, pelo roteiro ou pela linha; exige = o que a 7c pede da etapa. Ao dono a palavra é "etapa" (agenda_tasks são as tarefas dele). Não se apaga; muda o texto, o peso, a ordem, a máscara e o estado (viva → feita/nao_se_aplica/saiu/substituida; feita → viva). Escreve só _agenda_tarefas_sincronizar, _agenda_tarefas_registrar, _agenda_tarefas_conferir e _agenda_aplicar_etapa.';
comment on column public.os_tarefas.pendente_vezes is 'Em quantos dias diferentes a etapa ficou pendente (equipe, dono ou conferência; o sem_registro não conta), desde pendente_desde; zera quando é feita. Em tarefas_pendente_alerta, a ação tarefa ao dono.';
comment on column public.os_tarefas.nova_no_escopo is 'A etapa entrou depois da 1ª sincronização (o orçamento aumentou ou o dono acrescentou): fica no fim, antes de testar e entregar.';

create table if not exists public.os_tarefas_dia (
  id               uuid primary key default gen_random_uuid(),
  tarefa_id        uuid not null references public.os_tarefas(id) on delete cascade,
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  dia              date not null,
  turno            text not null check (turno in ('manha', 'tarde')),
  modo             text not null check (modo in ('sombra', 'ligado')),
  fracao           numeric(4,3) not null check (fracao > 0 and fracao <= 1),
  comeca           boolean not null,
  termina          boolean not null,
  posicao          smallint not null check (posicao between 1 and 50),
  equipe           uuid[] not null default '{}',
  responde         uuid references public.payees(id) on delete set null,       -- nulo = o dono (vale a conferência)
  estado           text not null check (estado in ('planejada', 'cancelada')),
  resultado        text check (resultado in ('feita', 'pendente', 'sem_registro')),
  resultado_via    text check (resultado_via in ('equipe', 'dono', 'conferencia', 'roteiro')),
  resultado_em     timestamptz,
  resultado_trecho text check (char_length(resultado_trecho) <= 500),
  mensagem_id      uuid references public.agenda_equipe_mensagens(id) on delete set null,
  congelada_em     timestamptz not null,
  cancelada_em     timestamptz,
  constraint os_tarefas_dia_resultado_coerente check ((resultado is null) = (resultado_em is null)
                                                      and (resultado is null) = (resultado_via is null)),
  constraint os_tarefas_dia_so_termina check (resultado is null or termina),
  constraint os_tarefas_dia_cancelada check ((estado = 'cancelada') = (cancelada_em is not null))
);
create unique index if not exists os_tarefas_dia_uma on public.os_tarefas_dia(tarefa_id, dia, turno, modo) where estado = 'planejada';
create index if not exists os_tarefas_dia_meio on public.os_tarefas_dia(service_order_id, dia, turno, modo) where estado = 'planejada';

comment on table public.os_tarefas_dia is
  'Agenda de Produção (Fase 7c, P8; AG7-10): o plano do dia congelado — o que cada meio-dia marcado da OS leva de cada etapa (fracao do meio-dia de trabalho; comeca/termina; a posição no meio-dia), a equipe e quem responde (o responsável da OS ou da equipe; nulo = o dono pela conferência, também quando quem responderia não recebe pelo WhatsApp). Congela uma vez por (OS, dia, turno, modo): o de amanhã antes da ficha das 19:30, o de hoje no 1º tique do dia; o meio-dia que perdeu a alocação vira cancelada. Sombra e ligado nunca se misturam. O resultado (feita, pendente, sem_registro) só na linha que termina; a palavra do dono vale sobre a da equipe, e a da equipe sobre a conferência. Não se apaga.';

-- Não se apaga (o de Fase 2); a etapa muda só o texto, o peso, a ordem, a máscara e o estado (viva → qualquer outro; feita → viva).
create or replace function public._os_tarefas_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new),
                                 array['texto', 'fase', 'ordem', 'horas', 'exige', 'passos', 'estado', 'feita_em', 'feita_via',
                                       'pendente_vezes', 'pendente_desde', 'pendente_ultimo', 'mudou_em'],
                                 array['criada_por', 'service_order_service_id', 'pai_id']) then
    raise exception 'os_tarefas: a etapa não muda de OS, de chave nem de origem (o rastro fica).' using errcode = '23514';
  end if;
  if new.estado is distinct from old.estado
     and not (old.estado = 'viva' or (old.estado = 'feita' and new.estado = 'viva')) then
    raise exception 'os_tarefas: a etapa não vai de % para %.', old.estado, new.estado using errcode = '23514';
  end if;
  return new;
end;
$function$;

comment on function public._os_tarefas_so_muda() is
  'Agenda de Produção (Fase 7c, P8): gatilho BEFORE UPDATE de os_tarefas — mudam só texto, fase, ordem, horas, exige, passos, estado, feita_*, pendente_* e mudou_em (as referências podem virar nulas pela FK); o estado vai de viva a qualquer outro e de feita a viva (o "ainda falta" do dono). O resto = 23514.';

create or replace function public._os_tarefas_dia_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new),
                                 array['resultado', 'resultado_via', 'resultado_em', 'resultado_trecho', 'mensagem_id', 'estado',
                                       'cancelada_em'],
                                 array['responde']) then
    raise exception 'os_tarefas_dia: o plano do dia congelado não muda; só o resultado e o estado.' using errcode = '23514';
  end if;
  if new.estado is distinct from old.estado and not (old.estado = 'planejada' and new.estado = 'cancelada') then
    raise exception 'os_tarefas_dia: a linha não vai de % para %.', old.estado, new.estado using errcode = '23514';
  end if;
  return new;
end;
$function$;

comment on function public._os_tarefas_dia_so_muda() is
  'Agenda de Produção (Fase 7c, P8): gatilho BEFORE UPDATE de os_tarefas_dia — mudam só resultado, resultado_via, resultado_em, resultado_trecho, mensagem_id, estado (de planejada a cancelada) e cancelada_em (quem responde pode virar nulo pela FK). O resto = 23514.';

drop trigger if exists os_tarefas_nao_apaga on public.os_tarefas;
create trigger os_tarefas_nao_apaga before delete on public.os_tarefas
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists os_tarefas_so_muda on public.os_tarefas;
create trigger os_tarefas_so_muda before update on public.os_tarefas
  for each row execute function public._os_tarefas_so_muda();
drop trigger if exists os_tarefas_dia_nao_apaga on public.os_tarefas_dia;
create trigger os_tarefas_dia_nao_apaga before delete on public.os_tarefas_dia
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists os_tarefas_dia_so_muda on public.os_tarefas_dia;
create trigger os_tarefas_dia_so_muda before update on public.os_tarefas_dia
  for each row execute function public._os_tarefas_dia_so_muda();

alter table public.os_tarefas enable row level security;
alter table public.os_tarefas_dia enable row level security;
drop policy if exists os_tarefas_leitura on public.os_tarefas;
create policy os_tarefas_leitura on public.os_tarefas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));
drop policy if exists os_tarefas_dia_leitura on public.os_tarefas_dia;
create policy os_tarefas_dia_leitura on public.os_tarefas_dia
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));
revoke all on table public.os_tarefas, public.os_tarefas_dia from public, anon, authenticated;
grant select on table public.os_tarefas, public.os_tarefas_dia to authenticated;
grant all on table public.os_tarefas, public.os_tarefas_dia to service_role;

-- ── 4. As listas fechadas (o ampliador da 7a: lê a lista viva e soma; a coluna critica não muda) ─────────────────────────────
select public._agenda_ampliar_lista('public.agenda_perguntas', 'agenda_perguntas_tipo_check', 'tipo', array['tarefa']);
select public._agenda_ampliar_lista('public.agenda_acoes', 'agenda_acoes_tipo_check', 'tipo', array['tarefa']);
select public._agenda_ampliar_lista('public.agenda_rascunho', 'agenda_rascunho_tipo_check', 'tipo', array['etapa']);
select public._agenda_ampliar_lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', 'rotina', array['tarefas']);

-- ── 5. O texto, a fase e a fonte das etapas (spec §16.3.2, §16.3.3, §16.5.1) ────────────────────────────────────────────────

-- O texto da etapa pelo nome da linha (§16.3.2): sem a caixa alta (frase_legivel), sem o prefixo "Mão de obra - " / "Serviço de", sem o
-- parêntese do fim; acima de p_max (o tarefas_texto_max), corta no 1º " — ", " – " ou ": " com 12 letras ou mais antes, senão na última
-- palavra que cabe, sem a pontuação do fim, com "…".
create or replace function public._agenda_tarefa_texto(p_nome text, p_max integer default 60)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_max int := least(greatest(coalesce(p_max, 60), 30), 80);
  v     text;
  v_i   int;
  v_c   text := '';
  w     text;
begin
  v := regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g');
  if v = '' then
    return null;
  end if;
  v := public.frase_legivel(v);
  v := btrim(regexp_replace(regexp_replace(v, '^(m[ãa]o de obra|servi[çc]o)\s*(de\s+|[-–—:]\s*)', '', 'i'), '\s*\([^)]*\)\s*$', ''));
  if char_length(v) < 3 then
    v := btrim(public.frase_legivel(regexp_replace(btrim(p_nome), '\s+', ' ', 'g')));
  end if;
  v := upper(left(v, 1)) || substr(v, 2);
  if char_length(v) > v_max then
    select min(x.p) into v_i
      from (select nullif(strpos(v, s), 0) as p from unnest(array[' — ', ' – ', ': ']) s) x;
    if v_i is not null and v_i - 1 >= 12 then
      v := rtrim(left(v, v_i - 1));
    end if;
  end if;
  if char_length(v) > v_max then
    foreach w in array regexp_split_to_array(v, ' ') loop
      exit when char_length(v_c) + case when v_c = '' then 0 else 1 end + char_length(w) > v_max - 1;
      v_c := v_c || case when v_c = '' then '' else ' ' end || w;
    end loop;
    if v_c = '' then
      v_c := left(v, v_max - 1);
    end if;
    v := regexp_replace(v_c, '[\s,;:.—–-]+$', '') || '…';
  end if;
  return left(v, 80);
end;
$function$;

comment on function public._agenda_tarefa_texto(text, integer) is
  'Agenda de Produção (Fase 7c, P8; spec §16.3.2): o texto da etapa pelo nome da linha — frase_legivel (sem a caixa alta), sem o prefixo "Mão de obra - " / "Serviço de", sem o parêntese do fim; acima de p_max (tarefas_texto_max, 30 a 80), corta no 1º " — ", " – " ou ": " quando o pedaço antes tem 12 letras ou mais, senão na última palavra que cabe, sem a pontuação do fim, com "…" ("SERVIÇO DE PASSAGEM E CRIMPAGEM DE CABOS DE BATERIA" → "Passagem e crimpagem de cabos de bateria"; "Conversão do sistema de refrigeração para 12V — Refrigerador Consul CRC28FB" → "Conversão do sistema de refrigeração para 12V"). Vazio = nulo. IMMUTABLE; authenticated e service_role.';

-- A fase da etapa (§16.3.3): pelo nome do serviço (_agenda_nome_do_servico: normalizado, antes do travessão, dos dois pontos ou do
-- parêntese), a 1ª regex de p_fases (tarefas_fases) que casa, na ordem; senão executar (3).
create or replace function public._agenda_tarefa_fase(p_nome text, p_fases jsonb)
 returns smallint
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce((select (e ->> 1)::smallint
                     from jsonb_array_elements(coalesce(p_fases, '[]'::jsonb)) with ordinality t(e, o)
                    where public._agenda_nome_do_servico(p_nome) ~ (e ->> 2)
                    order by o limit 1), 3::smallint);
$function$;

comment on function public._agenda_tarefa_fase(text, jsonb) is
  'Agenda de Produção (Fase 7c, P8; spec §16.3.3; AG7-10a): a fase da etapa pelo nome do serviço (_agenda_nome_do_servico) — a 1ª regex de p_fases (tarefas_fases: testar 5, entregar 6, configurar 4, desmontar 2, diagnosticar 1, nessa ordem de avaliação) que casa; senão executar (3). "Religação do Inversor (… remoção/fixação)" é executar: o corte no "(" evita a falsa desmontagem. IMMUTABLE; authenticated e service_role.';

-- As etapas que a OS tem pela base de hoje, sem gravar nada (§16.3.2, §16.5.1).
create or replace function public.os_tarefas_fonte(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_bits   constant jsonb := '{"energizado": 1, "comissionamento": 2, "altura": 4, "diagnostico": 8}';
  cf       public.agenda_config;
  v_uid    uuid := auth.uid();
  v_papel  text;
  v_mo     numeric;
  v_ex     jsonb;
  v_todos  int := 0;      -- o que a OS pede sem linha, em todos os dias: vai a toda etapa
  v_ult    int := 0;      -- o que a OS pede no último dia (com ou sem linha): vai à etapa final
  v_rot    boolean;
  v_itens  jsonb := '[]'::jsonb;
  v_fora   jsonb := '[]'::jsonb;
  v_final  jsonb;
  v_sist   text[];
  v_min    numeric;
  v_txt    text;
  r        record;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (a rodada, a vigia).
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'As etapas da OS são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'As etapas da OS são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_os is null or not exists (select 1 from public.service_orders so where so.id = p_os) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  cf := public._agenda_cfg();
  v_mo := nullif(public._agenda_mo_por_diaria_real(), 0);

  -- O que a OS pede (7c P1): as linhas levam o delas; o sem linha em todos os dias vai a toda etapa; o do último dia, à etapa final.
  v_ex := public.os_exigencias(p_os, p_hoje);
  select coalesce(bit_or((c_bits ->> (i ->> 'exigencia'))::int) filter (where i ->> 'linha_id' is null and i ->> 'meios' = 'todos'), 0),
         coalesce(bit_or((c_bits ->> (i ->> 'exigencia'))::int) filter (where i ->> 'meios' = 'ultimo'), 0)
    into v_todos, v_ult
    from jsonb_array_elements(coalesce(v_ex -> 'itens', '[]'::jsonb)) i;

  v_rot := exists (select 1 from public.service_order_steps st where st.service_order_id = p_os);

  -- As linhas, cada uma com a régua da mão de obra (a de os_duracao_sugerida e da 7c: o material de texto livre, o deslocamento pelo
  -- mo_fora_regex, a logística e o sistema nenhum ficam de fora), o peso e, com roteiro, o bloco dela.
  for r in
    with l as (
      select s.id, s.name_snapshot as nome, s.created_at as criado, s.billing_unit_snapshot as un, coalesce(s.quantity, 0) as q,
             coalesce(s.line_total, 0) as tot,
             case when s.service_id is null and s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0
                       and public.free_text_is_material(s.name_snapshot) then 'material'
                  when public._agenda_nome_do_servico(s.name_snapshot) ~ cf.mo_fora_regex then 'deslocamento'
                  when coalesce(s.service_verb, sv.service_verb, '') = 'logistica' then 'logistica'
                  when coalesce(s.service_system, sv.service_system, '') = 'nenhum' then 'nao_e_servico' end as fora,
             (select array_agg(st.id order by st.seq, st.id) from public.service_order_steps st
               where st.service_order_id = p_os and st.block_key = 'linha:' || s.id::text) as passos,
             (select min(st.seq) from public.service_order_steps st
               where st.service_order_id = p_os and st.block_key = 'linha:' || s.id::text) as seq0
        from public.service_order_services s
        left join public.services sv on sv.id = s.service_id
       where s.service_order_id = p_os and btrim(coalesce(s.name_snapshot, '')) <> ''
    )
    select l.*, row_number() over (order by l.criado, l.id) as n from l order by l.criado, l.id
  loop
    if r.fora is not null then
      v_fora := v_fora || jsonb_build_array(jsonb_build_object('linha', r.id, 'nome', r.nome, 'motivo', r.fora));
      continue;
    end if;
    v_txt := public._agenda_tarefa_texto(r.nome, cf.tarefas_texto_max);
    v_itens := v_itens || jsonb_build_array(jsonb_build_object(
      'chave', 'linha:' || r.id::text,
      'origem', case when v_rot and r.passos is not null then 'roteiro' else 'orcamento' end,
      'service_order_service_id', r.id,
      'texto', v_txt,
      'fase', public._agenda_tarefa_fase(r.nome, cf.tarefas_fases),
      -- dentro da fase: o seq do 1º passo do bloco (com roteiro) ou a ordem da linha (sem; a linha que entrou depois do roteiro, depois)
      'ordem_origem', case when v_rot and r.passos is not null then r.seq0 else 100000 + r.n end,
      'horas', round(greatest(case when r.un = 'hour' then r.q else 0 end,
                              case when v_mo is null then 0 else r.tot / v_mo * cf.jornada_horas end,
                              cf.tarefas_horas_min), 2),
      'exige', v_todos
               | coalesce((select bit_or((c_bits ->> (i ->> 'exigencia'))::int)
                             from jsonb_array_elements(coalesce(v_ex -> 'itens', '[]'::jsonb)) i
                            where i ->> 'linha_id' = r.id::text), 0),
      'passos', to_jsonb(coalesce(r.passos, '{}'::uuid[]))));
  end loop;
  -- O bloco do roteiro de uma linha que não é serviço (deslocamento, material) fica de fora junto com ela (acima). A abertura nunca é
  -- etapa: é a rotina de segurança de cada começo de dia, que a via já imprime.

  -- A etapa final: com roteiro, os blocos fechamento:<sistema> dele; sem roteiro, os blocos fechamento de seguranca_da_via (os sistemas
  -- das linhas). O peso: os minutos dos blocos ÷ 60 (no mínimo tarefas_horas_min).
  if v_rot then
    select array_agg(x.sist order by x.seq0), sum(x.minutos)
      into v_sist, v_min
      from (select substr(st.block_key, length('fechamento:') + 1) as sist, min(st.seq) as seq0,
                   coalesce(sum(st.standard_minutes), 0) as minutos
              from public.service_order_steps st
             where st.service_order_id = p_os and st.block_key like 'fechamento:%'
             group by 1) x;
    if cardinality(v_sist) > 0 then
      v_final := jsonb_build_object('origem', 'roteiro',
        'passos', to_jsonb(array(select st.id from public.service_order_steps st
                                  where st.service_order_id = p_os and st.block_key like 'fechamento:%' order by st.seq, st.id)),
        'ordem_origem', (select min(st.seq) from public.service_order_steps st
                          where st.service_order_id = p_os and st.block_key like 'fechamento:%'));
    end if;
  else
    select array_agg(x.sist order by x.o), sum(x.minutos)
      into v_sist, v_min
      from (select v.sistema as sist, min(v.ord) as o, coalesce(sum(v.standard_minutes), 0) as minutos
              from (select g.*, row_number() over () as ord from public.seguranca_da_via(p_os) g) v
             where v.papel = 'fechamento'
             group by v.sistema) x;
    if cardinality(v_sist) > 0 then
      v_final := jsonb_build_object('origem', 'seguranca', 'passos', '[]'::jsonb, 'ordem_origem', 999999);
    end if;
  end if;
  if v_final is not null then
    v_txt := 'Testar e conferir antes de entregar ('
             || public._agenda_lista(array(select public.service_system_label(s) from unnest(v_sist) with ordinality u(s, o) order by o), null)
             || ')';
    if char_length(v_txt) > cf.tarefas_texto_max then
      v_txt := 'Testar e conferir tudo antes de entregar';
    end if;
    v_itens := v_itens || jsonb_build_array(v_final || jsonb_build_object(
      'chave', 'entrega', 'service_order_service_id', null, 'texto', v_txt, 'fase', 6,
      'horas', round(greatest(coalesce(v_min, 0) / 60, cf.tarefas_horas_min), 2),
      'exige', v_todos | v_ult));
  end if;

  -- Na ordem do serviço: a fase, depois a do roteiro ou da linha; a final por último.
  select coalesce(jsonb_agg(i order by (i ->> 'fase')::int, (i ->> 'ordem_origem')::numeric, i ->> 'chave'), '[]'::jsonb)
    into v_itens
    from jsonb_array_elements(v_itens) i;
  return jsonb_build_object('ok', true, 'roteiro', v_rot, 'itens', v_itens, 'fora', v_fora,
                            'assinatura', md5(coalesce((select jsonb_agg(i - 'exige' order by o)
                                                          from jsonb_array_elements(v_itens) with ordinality t(i, o)), '[]'::jsonb)::text));
end;
$function$;

comment on function public.os_tarefas_fonte(uuid, date) is
  'Agenda de Produção (Fase 7c, P8; spec §16.3.2, §16.5.1): as etapas que a OS tem pela base de hoje, sem gravar nada — {ok, roteiro, itens [{chave (linha:<sos> | entrega), origem (roteiro | orcamento | seguranca), service_order_service_id, texto, fase, ordem_origem, horas, exige, passos}], fora [{linha, nome, motivo material | deslocamento | logistica | nao_e_servico}], assinatura (md5 dos itens sem a máscara)}. Com roteiro: cada bloco linha:<sos> cuja linha passa na régua da mão de obra (a de os_duracao_sugerida) é uma etapa, a linha sem bloco também (orcamento, depois das do roteiro), e os blocos fechamento:* são a etapa final; a abertura não é etapa. Sem roteiro: cada linha que passa na régua e a etapa final pelos blocos fechamento de seguranca_da_via. O peso: max(horas da linha cobrada por hora, valor ÷ R$ por diária × jornada, tarefas_horas_min); a final, os minutos dos blocos ÷ 60. A máscara (os bits da 7c), de os_exigencias: a da linha, mais o sem linha em todos os dias em toda etapa; a final leva também o do último dia. OS que não existe = {ok: false, texto}. Com login, só admin/financeiro (42501); sem login, só o service_role. STABLE; definer (a spec dizia invoker: as peças de dentro não têm grant); authenticated e service_role.';

-- A sincronização (§16.5.1): as etapas gravadas seguem a base — a de mesma chave atualiza (texto, fase, peso, máscara, passos; o estado
-- fica), a nova entra (na 1ª vez pela ordem do serviço; depois, no fim, antes de testar e entregar, com a ação ao dono), a que saiu da base
-- vira saiu (a feita fica feita). As do dono e as partes de uma divisão não são tocadas.
create or replace function public._agenda_tarefas_sincronizar(p_os uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_casa   constant numeric := 0.001;   -- estrutural: a menor casa de os_tarefas.ordem (numeric(8,3))
  cf      public.agenda_config := public._agenda_cfg();
  v_f     jsonb;
  v_ass   text;
  v_prim  boolean;
  i       jsonb;
  t       public.os_tarefas%rowtype;
  v_novas text[] := '{}';
  v_saiu  int := 0;
  v_atu   int := 0;
  v_n     int := 0;
  v_ord   numeric;
  v_x     numeric;
  v_ant   numeric;
  v_qtd   int;
  v_pass  uuid[];
  v_cli   text;
  v_txt   text;
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception 'Faltam a OS, o dia e a hora para sincronizar as etapas.' using errcode = '22023';
  end if;
  v_f := public.os_tarefas_fonte(p_os, p_hoje);
  if not coalesce((v_f ->> 'ok')::boolean, false) then
    return jsonb_build_object('ok', false, 'mudou', false);
  end if;
  select pl.tarefas_assinatura into v_ass from public.os_planejamento pl where pl.service_order_id = p_os;
  v_prim := not exists (select 1 from public.os_tarefas x where x.service_order_id = p_os);
  if not v_prim and v_ass is not distinct from (v_f ->> 'assinatura')
     and not exists (select 1 from jsonb_array_elements(v_f -> 'itens') e
                       join public.os_tarefas x on x.service_order_id = p_os and x.chave = e ->> 'chave' and x.estado in ('viva', 'feita')
                      where x.exige <> (e ->> 'exige')::int) then
    return jsonb_build_object('ok', true, 'mudou', false, 'novas', 0, 'saiu', 0, 'atualizadas', 0, 'escopo', '[]'::jsonb);
  end if;

  for i in select e from jsonb_array_elements(v_f -> 'itens') with ordinality t(e, o) order by o loop
    v_n := v_n + 1;
    v_pass := array(select x::uuid from jsonb_array_elements_text(coalesce(i -> 'passos', '[]'::jsonb)) x);
    select * into t from public.os_tarefas x
     where x.service_order_id = p_os and x.chave = i ->> 'chave' and x.estado in ('viva', 'feita') limit 1;
    if found then
      if (t.texto, t.fase, t.horas, t.exige, t.passos)
         is distinct from (i ->> 'texto', (i ->> 'fase')::smallint, (i ->> 'horas')::numeric, (i ->> 'exige')::smallint, v_pass) then
        update public.os_tarefas
           set texto = i ->> 'texto', fase = (i ->> 'fase')::smallint, horas = (i ->> 'horas')::numeric,
               exige = (i ->> 'exige')::smallint, passos = v_pass, mudou_em = p_agora
         where id = t.id;
        v_atu := v_atu + 1;
      end if;
      continue;
    end if;
    -- a dividida: as partes recebem o peso ÷ n e a máscara dela
    select * into t from public.os_tarefas x
     where x.service_order_id = p_os and x.chave = i ->> 'chave' and x.estado = 'substituida' order by x.mudou_em desc, x.id limit 1;
    if found then
      select count(*) into v_qtd from public.os_tarefas p where p.pai_id = t.id and p.estado in ('viva', 'feita');
      if v_qtd > 0 then
        update public.os_tarefas p
           set horas = round((i ->> 'horas')::numeric / v_qtd, 2), exige = (i ->> 'exige')::smallint, mudou_em = p_agora
         where p.pai_id = t.id and p.estado in ('viva', 'feita')
           and (p.horas, p.exige) is distinct from (round((i ->> 'horas')::numeric / v_qtd, 2), (i ->> 'exige')::smallint);
      end if;
      continue;
    end if;
    -- a nova: na 1ª vez, pela ordem do serviço; depois, no fim, antes da 1ª viva de fase >= testar (a de fase >= 5, antes da final)
    if v_prim then
      v_ord := v_n;
    else
      if (i ->> 'fase')::int >= 5 then
        select min(x.ordem) into v_x from public.os_tarefas x where x.service_order_id = p_os and x.estado = 'viva' and x.chave = 'entrega';
      else
        select min(x.ordem) into v_x from public.os_tarefas x where x.service_order_id = p_os and x.estado = 'viva' and x.fase >= 5;
      end if;
      if v_x is null then
        select coalesce(max(x.ordem), 0) + 1 into v_ord from public.os_tarefas x where x.service_order_id = p_os;
      else
        select coalesce(max(x.ordem), v_x - 1) into v_ant from public.os_tarefas x where x.service_order_id = p_os and x.ordem < v_x;
        v_ord := round((v_ant + v_x) / 2, 3);
        if v_ord <= v_ant or v_ord >= v_x then
          v_ord := v_x - c_casa;
        end if;
      end if;
    end if;
    insert into public.os_tarefas (service_order_id, chave, origem, service_order_service_id, texto, fase, ordem, horas, exige, passos,
                                   estado, nova_no_escopo, criada_em, mudou_em)
    values (p_os, i ->> 'chave', i ->> 'origem', (i ->> 'service_order_service_id')::uuid, i ->> 'texto', (i ->> 'fase')::smallint,
            v_ord, (i ->> 'horas')::numeric, (i ->> 'exige')::smallint, v_pass, 'viva', not v_prim, p_agora, p_agora);
    if not v_prim then
      v_novas := v_novas || (i ->> 'texto');
    end if;
  end loop;

  -- A que saiu da base (a linha apagada, virou material): saiu. A feita fica feita; as do dono e as partes não são tocadas.
  update public.os_tarefas x
     set estado = 'saiu', mudou_em = p_agora
   where x.service_order_id = p_os and x.estado = 'viva' and x.pai_id is null and (x.chave like 'linha:%' or x.chave = 'entrega')
     and not exists (select 1 from jsonb_array_elements(v_f -> 'itens') e where e ->> 'chave' = x.chave);
  get diagnostics v_saiu = row_count;

  -- O escopo que aumentou: UMA ação ao dono (no "o que mudou"), em teste com "Em teste: ".
  if cardinality(v_novas) > 0 and cf.modo_tarefas <> 'desligado' then
    v_cli := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so join public.clients cl on cl.id = so.client_id
                        where so.id = p_os), public._agenda_rotulo_da_os(p_os));
    v_txt := format('%s: entrou %s (o orçamento aumentou). %s no fim%s', v_cli,
                    public._agenda_lista(array(select '"' || x || '"' from unnest(v_novas) with ordinality u(x, o) order by o), null),
                    case when cardinality(v_novas) = 1 then 'Ficou' else 'Ficaram' end,
                    case when exists (select 1 from public.os_tarefas x where x.service_order_id = p_os and x.estado = 'viva' and x.fase >= 5
                                         and not (x.texto = any (v_novas)))
                         then ', antes de testar e entregar.' else '.' end);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), p_hoje, cf.modo_tarefas = 'ligado', 'vigia', 'tarefa', p_os, array[p_os],
            jsonb_build_object('os', p_os, 'novas', to_jsonb(v_novas)), jsonb_build_object('motivo', 'escopo'),
            left(case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end || v_txt, 400));
  end if;

  insert into public.os_planejamento (service_order_id, tarefas_assinatura, tarefas_sincronizadas_em)
  values (p_os, v_f ->> 'assinatura', p_agora)
  on conflict (service_order_id) do update
    set tarefas_assinatura = excluded.tarefas_assinatura, tarefas_sincronizadas_em = excluded.tarefas_sincronizadas_em;
  return jsonb_build_object('ok', true, 'mudou', true, 'novas', cardinality(v_novas), 'saiu', v_saiu, 'atualizadas', v_atu,
                            'escopo', to_jsonb(v_novas), 'primeira', v_prim);
end;
$function$;

comment on function public._agenda_tarefas_sincronizar(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.1): as etapas gravadas (os_tarefas) seguem a base (os_tarefas_fonte) — a mesma assinatura e a mesma máscara = {mudou: false}; senão a etapa viva ou feita de mesma chave atualiza texto, fase, peso, máscara e passos (o estado fica), a dividida passa o peso ÷ n e a máscara às partes, a nova entra viva (na 1ª sincronização pela ordem do serviço; depois com nova_no_escopo, logo antes da 1ª viva de fase >= testar — a de fase >= 5, logo antes da final), a viva de chave linha:*/entrega que saiu da base vira saiu (a feita fica feita; as do dono e as partes não são tocadas). Com etapa nova do escopo e modo_tarefas fora de desligado: UMA ação tarefa (origem vigia, executada = ligado, sem *desfaz*, antes {os, novas}) — "Flávio: entrou "Instalação do compressor e recarga de gás" (o orçamento aumentou). Ficou no fim, antes de testar e entregar." (em teste com "Em teste: "). Grava os_planejamento.tarefas_assinatura e tarefas_sincronizadas_em. {ok, mudou, novas, saiu, atualizadas, escopo, primeira}. Definer, sem grant.';

-- A distribuição (§16.3.5, R5.2-3): em cada meio-dia marcado da OS, de p_hoje em diante, cabe até um meio-dia de trabalho; a pendente vem
-- primeiro, depois a começada, depois as outras pela ordem; a etapa de risco só vai a meio-dia cuja equipe atende (_agenda_atende). O
-- meio-dia já congelado (deste modo) entra com as linhas dele. A que terminou sem resultado ou ficou sem registro conta como feita para o
-- plano (só a pendente dita volta). STABLE: só lê.
create or replace function public._agenda_tarefas_planejar(p_os uuid, p_hoje date, p_modo text)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_resto  constant numeric := 0.25;    -- estrutural (spec §16.3.6): a etapa começada pede ao menos ¼ de meio-dia
  c_resid  constant numeric := 0.001;   -- estrutural: o resíduo das frações (3 casas) não é etapa a fazer
  c_folga  constant numeric := 0.01;    -- estrutural: a sobra de um meio-dia abaixo disso não leva outra etapa
  cf       public.agenda_config := public._agenda_cfg();
  v_dono   uuid := public._agenda_dono(null);
  v_n      jsonb;
  v_total  numeric;
  v_soma   numeric;
  v_ids    uuid[] := '{}';
  v_meios  numeric[] := '{}';
  v_need   numeric[] := '{}';
  v_ex     int[] := '{}';
  v_fin    boolean[] := '{}';
  v_ini    boolean[] := '{}';
  v_pend   boolean[] := '{}';
  v_pdia   date[] := '{}';
  v_ord    numeric[] := '{}';
  v_at     boolean[] := '{}';
  v_k      int;
  e        record;
  l        record;
  r        record;
  v_md     jsonb := '[]'::jsonb;
  v_hab    jsonb := '{}'::jsonb;
  v_fone   jsonb := '{}'::jsonb;
  v_dalt   int;
  v_lid    uuid;
  h        record;
  v_pes    uuid[];
  v_out    jsonb := '[]'::jsonb;
  v_itens  jsonb;
  v_cap    numeric;
  v_pos    int;
  v_f      numeric;
  v_term   boolean;
  v_fila   int[];
  v_atende boolean;
  v_mask   int;
  v_resp   uuid;
  v_prazo  date;
  v_snap   numeric;
  v_ate    int := 0;
  v_falta  numeric;
  v_futuro int := 0;
  v_faltam uuid[];
  m        jsonb;
begin
  if p_os is null or p_hoje is null or p_modo is null or p_modo not in ('sombra', 'ligado') then
    raise exception 'Faltam a OS, o dia e o modo (sombra ou ligado) para planejar as etapas.' using errcode = '22023';
  end if;
  v_n := jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                            'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura, 'par', cf.habilidade_nivel_par);
  v_total := nullif((public.agenda_meios_da_os(p_os, p_hoje) ->> 'total')::numeric, 0);
  select coalesce(sum(x.horas), 0) into v_soma from public.os_tarefas x where x.service_order_id = p_os and x.estado in ('viva', 'feita');

  -- 1. As etapas vivas, cada uma com o que ainda pede (need), pelo que o plano congelado de antes de hoje levou.
  for e in select x.* from public.os_tarefas x where x.service_order_id = p_os and x.estado = 'viva' order by x.ordem, x.id loop
    v_ids := v_ids || e.id;
    v_ord := v_ord || e.ordem;
    v_ex := v_ex || e.exige::int;
    v_fin := v_fin || (e.chave = 'entrega');
    v_meios := v_meios || case when v_total is not null and v_soma > 0 then e.horas / v_soma * v_total
                               else e.horas / (cf.jornada_horas / 2) end;
    v_k := cardinality(v_ids);
    v_need := v_need || v_meios[v_k];
    v_ini := v_ini || false;
    v_pend := v_pend || false;
    v_pdia := v_pdia || null::date;
    v_at := v_at || false;
    for l in select d.* from public.os_tarefas_dia d
              where d.tarefa_id = e.id and d.modo = p_modo and d.estado = 'planejada' and d.dia < p_hoje
              order by d.dia, d.turno = 'tarde', d.posicao loop
      v_need[v_k] := v_need[v_k] - l.fracao;
      v_ini[v_k] := true;
      if l.termina then
        if l.resultado = 'pendente' then
          v_need[v_k] := cf.tarefas_pendente_meios;
          v_ini[v_k] := false;
          v_pend[v_k] := true;
          v_pdia[v_k] := l.dia;
        else
          -- feita, sem registro (R5.2-3) ou ainda sem resultado: conta como feita para o plano
          v_need[v_k] := 0;
          v_ini[v_k] := false;
          v_pend[v_k] := false;
        end if;
      end if;
    end loop;
    if v_ini[v_k] and v_need[v_k] > 0 then
      v_need[v_k] := greatest(v_need[v_k], c_resto);
    elsif v_ini[v_k] and v_need[v_k] <= 0 then
      v_need[v_k] := c_resto;
    end if;
  end loop;
  v_falta := (select coalesce(sum(x), 0) from unnest(v_need) x where x > 0);
  v_faltam := array(select v_ids[k] from generate_subscripts(v_ids, 1) k where v_need[k] > c_resid
                     order by case when v_pend[k] then 0 when v_ini[k] then 1 else 2 end, v_pdia[k] nulls last, v_ord[k], k);

  -- 2. Os meios-dias da OS de hoje em diante (alocação vigente de turno, sem reserva): a equipe (sem o dono), o dono no turno, na
  -- abertura e no fechamento.
  select coalesce(jsonb_agg(jsonb_build_object('dia', x.dia, 'turno', x.turno, 'equipe', to_jsonb(x.eq), 'dono_turno', x.dt,
                                               'dono_fecha', x.df, 'dono_abre', x.da) order by x.dia, x.turno = 'tarde'), '[]'::jsonb)
    into v_md
    from (select a.dia, a.turno,
                 coalesce(array_agg(distinct a.payee_id) filter (where a.payee_id is distinct from v_dono), '{}'::uuid[]) as eq,
                 coalesce(bool_or(a.payee_id is not distinct from v_dono), false) as dt,
                 exists (select 1 from public.agenda_alocacoes b
                          where b.service_order_id = p_os and b.dia = a.dia and b.turno = a.turno and b.presenca = 'fechamento'
                            and b.payee_id is not distinct from v_dono and b.estado in ('publicada', 'fixada')) as df,
                 exists (select 1 from public.agenda_alocacoes b
                          where b.service_order_id = p_os and b.dia = a.dia and b.turno = a.turno and b.presenca = 'abertura'
                            and b.payee_id is not distinct from v_dono and b.estado in ('publicada', 'fixada')) as da
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
             and a.dia >= p_hoje
           group by a.dia, a.turno) x;

  -- As habilidades (uma leitura: as etiquetas efetivas, qualquer que seja o modo_habilidade, §16.3.5), quem recebe pelo WhatsApp e o
  -- responsável da OS.
  v_pes := array(select distinct u.x::uuid from jsonb_array_elements(v_md) d, jsonb_array_elements_text(d -> 'equipe') u(x));
  for h in select * from public.agenda_habilidades(p_hoje, v_pes || v_dono) loop
    v_hab := v_hab || jsonb_build_object(h.payee_id::text, jsonb_build_object('i', h.instala, 'c', h.comissiona, 'a', h.altura,
                                                                             'p', h.papel, 'n', h.nome));
    if h.eh_dono then
      v_dalt := h.altura;
    end if;
    v_fone := v_fone || jsonb_build_object(h.payee_id::text,
      public._agenda_equipe_tem_telefone(h.payee_id)
      and exists (select 1 from public.agenda_equipe_contato c where c.payee_id = h.payee_id and c.recebe_rotina and c.parou_em is null));
  end loop;
  v_lid := (public._agenda_lider_da_os(p_os, p_hoje) ->> 'payee_id')::uuid;
  v_prazo := (public.os_prontidao(p_os, p_hoje) ->> 'prazo_efetivo')::date;
  if v_prazo is null and jsonb_array_length(v_md) > 0 then
    v_prazo := (v_md -> -1 ->> 'dia')::date;
  end if;

  -- 3. Cada meio-dia, na ordem.
  for m in select d from jsonb_array_elements(v_md) d loop
    if v_snap is null and v_prazo is not null and (m ->> 'dia')::date > v_prazo then
      v_snap := (select coalesce(sum(x), 0) from unnest(v_need) x where x > 0);
    end if;
    -- o plano até o prazo: os meios-dias que ainda vão acontecer (o de hoje já congelado e todo respondido não conta mais)
    if v_prazo is not null and (m ->> 'dia')::date <= v_prazo
       and ((m ->> 'dia')::date > p_hoje
            or not exists (select 1 from public.os_tarefas_dia d
                            where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                              and d.estado = 'planejada')
            or exists (select 1 from public.os_tarefas_dia d
                        where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                          and d.estado = 'planejada' and d.termina and d.resultado is null)) then
      v_ate := v_ate + 1;
    end if;
    v_itens := '[]'::jsonb;
    if exists (select 1 from public.os_tarefas_dia d
                where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                  and d.estado = 'planejada') then
      -- congelado: entra com as linhas dele, sem refazer
      v_resp := null;
      for l in select d.* from public.os_tarefas_dia d
                where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno' and d.modo = p_modo
                  and d.estado = 'planejada'
                order by d.posicao, d.id loop
        v_resp := l.responde;
        v_k := array_position(v_ids, l.tarefa_id);
        if v_k is not null then
          v_need[v_k] := v_need[v_k] - l.fracao;
          v_ini[v_k] := true;
          v_pend[v_k] := false;
          if l.termina then
            if l.resultado = 'pendente' then
              v_need[v_k] := cf.tarefas_pendente_meios;
              v_ini[v_k] := false;
              v_pend[v_k] := true;
              v_pdia[v_k] := l.dia;
            else
              v_need[v_k] := 0;
              v_ini[v_k] := false;
            end if;
          elsif v_need[v_k] <= 0 then
            v_need[v_k] := c_resto;
          end if;
        end if;
        v_itens := v_itens || jsonb_build_array(jsonb_build_object('tarefa', l.tarefa_id, 'fracao', l.fracao, 'termina', l.termina,
                                                                   'comeca', l.comeca, 'posicao', l.posicao, 'linha_id', l.id,
                                                                   'resultado', l.resultado));
      end loop;
      v_out := v_out || jsonb_build_array(m || jsonb_build_object('congelado', true, 'responde', v_resp, 'itens', v_itens,
        'equipe', coalesce((select to_jsonb(d.equipe) from public.os_tarefas_dia d
                             where d.service_order_id = p_os and d.dia = (m ->> 'dia')::date and d.turno = m ->> 'turno'
                               and d.modo = p_modo and d.estado = 'planejada' order by d.posicao limit 1), m -> 'equipe')));
      continue;
    end if;

    v_futuro := v_futuro + 1;
    v_cap := 1;
    v_pos := 0;
    -- a fila deste meio-dia: a pendente (pela data, depois a ordem), a começada, as outras (pela ordem)
    v_fila := array(select k from generate_subscripts(v_ids, 1) k where v_need[k] > c_resid
                     order by case when v_pend[k] then 0 when v_ini[k] then 1 else 2 end, v_pdia[k] nulls last, v_ord[k], k);
    foreach v_k in array v_fila loop
      -- o fechamento do dono (com habilidade_fechamento_cobre) cobre a etapa final inteira e o comissionar e o diagnóstico das outras
      -- (o que é do dono, AG7-02); o 220 V e o teto pedem quem os faz na equipe do meio-dia
      v_mask := case when (m ->> 'dono_fecha')::boolean and cf.habilidade_fechamento_cobre
                     then case when v_fin[v_k] then 0 else v_ex[v_k] & ~10 end
                     else v_ex[v_k] end;
      if v_mask = 0 then
        v_atende := true;
      else
        v_atende := public._agenda_atende(
          v_mask,
          array(select (v_hab -> u.x ->> 'i')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          array(select (v_hab -> u.x ->> 'c')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          array(select (v_hab -> u.x ->> 'a')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          array(select (v_hab -> u.x ->> 'p')::int from jsonb_array_elements_text(m -> 'equipe') with ordinality u(x, o) order by u.o),
          (m ->> 'dono_turno')::boolean, v_dalt, v_n) is null;
      end if;
      if not v_atende then
        continue;   -- espera um meio-dia que atenda; as outras seguem
      end if;
      v_at[v_k] := true;
      continue when v_cap <= c_folga;
      v_f := least(v_need[v_k], v_cap);
      v_term := v_need[v_k] - v_f <= c_folga;
      if v_term then
        v_f := v_need[v_k];
      end if;
      v_f := least(greatest(round(v_f, 3), c_resid), 1);
      v_pos := v_pos + 1;
      v_itens := v_itens || jsonb_build_array(jsonb_build_object('tarefa', v_ids[v_k], 'fracao', v_f, 'termina', v_term,
                                                                 'comeca', not v_ini[v_k], 'posicao', v_pos, 'linha_id', null,
                                                                 'resultado', null));
      v_need[v_k] := case when v_term then 0 else v_need[v_k] - v_f end;
      v_ini[v_k] := true;
      v_pend[v_k] := false;
      v_cap := v_cap - v_f;
    end loop;

    -- quem responde pelas etapas do meio-dia (§16.3.6): o responsável da OS na equipe; senão o responsável da equipe de maior instala
    -- (o nome); senão, só com ajudante e o dono presente, o dono (nulo); senão o ajudante. Quem não recebe pelo WhatsApp (sem telefone
    -- pela régua da 7a, ou fora da rotina) não responde: vale a conferência do dono (nulo, R5.2-4).
    v_resp := null;
    if v_lid is not null and (m -> 'equipe') ? v_lid::text then
      v_resp := v_lid;
    else
      select u.x::uuid into v_resp
        from jsonb_array_elements_text(m -> 'equipe') u(x)
       where (v_hab -> u.x ->> 'p')::int = 0
       order by (v_hab -> u.x ->> 'i')::int desc, v_hab -> u.x ->> 'n', u.x limit 1;
      if v_resp is null and not ((m ->> 'dono_turno')::boolean or (m ->> 'dono_fecha')::boolean or (m ->> 'dono_abre')::boolean) then
        select u.x::uuid into v_resp from jsonb_array_elements_text(m -> 'equipe') u(x) order by v_hab -> u.x ->> 'n', u.x limit 1;
      end if;
    end if;
    if v_resp is not null and not coalesce((v_fone ->> v_resp::text)::boolean, false) then
      v_resp := null;
    end if;
    v_out := v_out || jsonb_build_array(m || jsonb_build_object('congelado', false, 'responde', v_resp, 'itens', v_itens));
  end loop;
  if v_snap is null then
    v_snap := (select coalesce(sum(x), 0) from unnest(v_need) x where x > 0);
  end if;

  return jsonb_build_object(
    'os', p_os, 'modo', p_modo, 'total', v_total, 'falta', round(v_falta, 3), 'faltam', to_jsonb(v_faltam), 'meios', v_out,
    'sobra', coalesce((select jsonb_agg(jsonb_build_object('tarefa', v_ids[k], 'need', round(v_need[k], 3)) order by k)
                         from generate_subscripts(v_ids, 1) k where v_need[k] > c_resid), '[]'::jsonb),
    'sobra_meios', round((select coalesce(sum(x), 0) from unnest(v_need) x where x > c_resid), 3),
    'sem_quem', coalesce((select jsonb_agg(v_ids[k] order by k) from generate_subscripts(v_ids, 1) k
                           where v_need[k] > c_resid and v_ex[k] <> 0 and not v_at[k] and v_futuro > 0), '[]'::jsonb),
    'prazo', v_prazo, 'sobra_no_prazo', round(v_snap, 3), 'meios_ate_prazo', v_ate);
end;
$function$;

comment on function public._agenda_tarefas_planejar(uuid, date, text) is
  'Agenda de Produção (Fase 7c, P8; spec §16.3.5, §16.3.6; R5.2-3, R5.2-4): a distribuição das etapas vivas da OS pelos meios-dias marcados (alocação vigente de turno, sem reserva) de p_hoje em diante, no modo p_modo — o que cada etapa pede em meios-dias é o peso dela sobre o total (agenda_meios_da_os.total; sem base, horas ÷ meia jornada) menos o que o plano congelado de antes de hoje levou (a começada, no mínimo 0,25; a pendente dita, tarefas_pendente_meios; a que terminou com feita, sem registro ou ainda sem resultado: nada, conta como feita para o plano). O meio-dia já congelado entra com as linhas dele; cada outro leva até 1,0, na fila pendente → começada → as outras pela ordem; a etapa de risco (exige) só vai ao meio-dia cuja equipe atende (_agenda_atende com as etiquetas efetivas; a final conta o fechamento do dono com habilidade_fechamento_cobre), e as outras seguem. Quem responde: o responsável da OS na equipe, senão o responsável da equipe de maior instala, senão (só ajudante e o dono presente) o dono (nulo), senão o ajudante; quem não recebe pelo WhatsApp (sem telefone pela régua da 7a ou fora da rotina) não responde (nulo = o dono pela conferência). {os, modo, total, falta, meios [{dia, turno, congelado, equipe, dono_turno, dono_fecha, dono_abre, responde, itens [{tarefa, fracao, termina, comeca, posicao, linha_id, resultado}]}], sobra [{tarefa, need}], sobra_meios, sem_quem [tarefa] (a de risco que nenhum meio-dia futuro atende), prazo (o prazo efetivo; sem ele, o último dia do plano), sobra_no_prazo (o que não coube até o prazo), meios_ate_prazo}. STABLE, sem grant.';

-- O texto do "como foi" ainda tem a lista de agora? (§16.3.7): todo item {n, texto} aparece como "n) <texto>".
create or replace function public._agenda_tarefas_texto_confere(p_texto text, p_lista jsonb)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_array_length(p_lista) > 0
                  and not exists (select 1 from jsonb_array_elements(p_lista) i
                                   where position(((i ->> 'n') || ') ' || (i ->> 'texto')) in coalesce(p_texto, '')) = 0), false);
$function$;

comment on function public._agenda_tarefas_texto_confere(text, jsonb) is
  'Agenda de Produção (Fase 7c, P8; spec §16.3.7): todo item {n, texto} de p_lista aparece em p_texto como "n) <texto>" (o "como foi" que a pessoa recebeu ainda é a lista de agora: os números valem). Lista vazia = falso. IMMUTABLE, sem grant.';

-- A lista "1) …; 2) …" (§16.5.2): os prefixos "Começar: ", "Continuar: ", "Terminar: ", o "(<cliente>) " de quem tem duas OS no dia e o
-- " — com <quem>" da etapa final com o dono; os primeiros que cabem em p_max_linhas e p_max_letras e "; e mais N". p_numeros = o "n) " (a
-- linha (o) do fechamento não numera: R5.10-10).
create or replace function public._agenda_tarefas_lista_texto(p_itens jsonb, p_max_linhas integer, p_max_letras integer,
                                                             p_prefixos boolean default true, p_numeros boolean default true)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_t   text[];
  v_n   int;
  v_k   int;
  v_txt text;
begin
  v_t := array(select case when coalesce(p_numeros, true) then (i ->> 'n') || ') ' else '' end
                      || case when not coalesce(p_prefixos, true) then ''
                              when coalesce((i ->> 'comeca')::boolean, true) and not coalesce((i ->> 'termina')::boolean, false) then 'Começar: '
                              when not coalesce((i ->> 'comeca')::boolean, true) and not coalesce((i ->> 'termina')::boolean, false) then 'Continuar: '
                              when not coalesce((i ->> 'comeca')::boolean, true) then 'Terminar: '
                              else '' end
                      || coalesce('(' || nullif(i ->> 'rotulo', '') || ') ', '')
                      || (i ->> 'texto')
                      || coalesce(' — com ' || nullif(i ->> 'com', ''), '')
                 from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) with ordinality t(i, o) order by o);
  v_n := cardinality(v_t);
  if v_n = 0 then
    return null;
  end if;
  v_k := least(v_n, greatest(coalesce(p_max_linhas, v_n), 1));
  loop
    v_txt := array_to_string(v_t[1:v_k], '; ') || case when v_k < v_n then format('; e mais %s', v_n - v_k) else '' end;
    exit when char_length(v_txt) <= coalesce(p_max_letras, 100000) or v_k = 1;
    v_k := v_k - 1;
  end loop;
  if char_length(v_txt) > coalesce(p_max_letras, 100000) then
    v_txt := public._agenda_corta(v_txt, p_max_letras);
  end if;
  return v_txt;
end;
$function$;

comment on function public._agenda_tarefas_lista_texto(jsonb, integer, integer, boolean, boolean) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.2): a lista do que fazer — "1) Terminar: Passagem e crimpagem de cabos de bateria; 2) Começar: Substituição baterias - chumbo para litio" — com os prefixos (p_prefixos: Começar = começa e não termina no dia, Continuar = nem começa nem termina, Terminar = começou antes e termina), o "(<rotulo>) " do item que traz rotulo (o cliente, quando a pessoa tem duas OS no dia), o " — com <com>" (a etapa final com o dono: "o Gustavo" à equipe, "você" ao dono) e o número de cada item (p_numeros; o "n" é o do dia, estável). Passou de p_max_linhas ou de p_max_letras: os primeiros que cabem e "; e mais N". Vazia = nulo. IMMUTABLE; authenticated e service_role (agenda_dia_da_pessoa e a linha do fechamento, invoker, a chamam).';

-- O dia da pessoa (§16.5.2): para cada OS em que ela tem alocação vigente de turno no dia, o que ela faz — as linhas congeladas do modo de
-- agora (o que passou) ou o planejar de hoje (de hoje em diante; ele traz os meios-dias congelados com as linhas deles). O item n é a
-- posição pela ordem (turno, início da OS no dia, OS, posição), uma vez por etapa no dia.
create or replace function public._agenda_tarefas_da_pessoa(p_payee uuid, p_dia date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config;
  v_uid   uuid := auth.uid();
  v_papel text;
  v_dono  uuid := public._agenda_dono(null);
  r       record;
  v_p     jsonb;
  v_lin   jsonb := '[]'::jsonb;
  v_meio  jsonb;
  it      jsonb;
  v_itens jsonb := '[]'::jsonb;
  v_ult   jsonb := '[]'::jsonb;
  v_prz   jsonb := '[]'::jsonb;
  v_resp  jsonb := '[]'::jsonb;
  v_nos   int;
  v_txt   jsonb := '{}'::jsonb;
  v_sobra text[];
  x       record;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (a rotina, a resposta da equipe, a rodada).
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'As etapas da OS são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'As etapas da OS são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  cf := public._agenda_cfg();
  if cf.modo_tarefas = 'desligado' or p_payee is null or p_dia is null or p_hoje is null then
    return jsonb_build_object('modo', cf.modo_tarefas, 'tem', false, 'itens', '[]'::jsonb, 'pergunta', '[]'::jsonb,
                              'ultimo_dia', '[]'::jsonb, 'prazo', '[]'::jsonb, 'responde', '[]'::jsonb);
  end if;

  for r in
    select a.service_order_id as os, min(lower(a.periodo)) as ini, array_agg(distinct a.turno) as turnos,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cliente
      from public.agenda_alocacoes a
      join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
     group by a.service_order_id, cl.name, so.service_order_number
     order by 2, 1
  loop
    v_sobra := '{}';
    if p_dia >= p_hoje then
      v_p := public._agenda_tarefas_planejar(r.os, p_hoje, cf.modo_tarefas);
      v_sobra := array(select t.texto from jsonb_array_elements(v_p -> 'sobra') s join public.os_tarefas t on t.id = (s ->> 'tarefa')::uuid
                        order by t.ordem, t.id);
      for v_meio in select d from jsonb_array_elements(v_p -> 'meios') d
                     where (d ->> 'dia')::date = p_dia and d ->> 'turno' = any (r.turnos) loop
        for it in select i from jsonb_array_elements(v_meio -> 'itens') i loop
          v_lin := v_lin || jsonb_build_array(it || jsonb_build_object(
            'os', r.os, 'ini', r.ini, 'cliente', r.cliente, 'turno', v_meio ->> 'turno', 'responde', v_meio -> 'responde',
            'com_dono', coalesce((v_meio ->> 'dono_turno')::boolean, false) or coalesce((v_meio ->> 'dono_fecha')::boolean, false)));
        end loop;
      end loop;
    else
      for x in select d.*, coalesce((select bool_or(b.presenca = 'fechamento') or bool_or(b.presenca = 'turno')
                                       from public.agenda_alocacoes b
                                      where b.service_order_id = d.service_order_id and b.dia = d.dia and b.turno = d.turno
                                        and b.payee_id is not distinct from v_dono and b.estado in ('publicada', 'fixada')), false) as cd
                 from public.os_tarefas_dia d
                where d.service_order_id = r.os and d.dia = p_dia and d.turno = any (r.turnos) and d.modo = cf.modo_tarefas
                  and d.estado = 'planejada'
                order by d.turno = 'tarde', d.posicao loop
        v_lin := v_lin || jsonb_build_array(jsonb_build_object(
          'tarefa', x.tarefa_id, 'fracao', x.fracao, 'termina', x.termina, 'comeca', x.comeca, 'posicao', x.posicao, 'linha_id', x.id,
          'resultado', x.resultado, 'os', r.os, 'ini', r.ini, 'cliente', r.cliente, 'turno', x.turno, 'responde', x.responde,
          'com_dono', x.cd));
      end loop;
    end if;
    -- o último dia da OS (nenhum meio-dia vigente de turno depois) e o dia do prazo
    if not exists (select 1 from public.agenda_alocacoes b
                    where b.service_order_id = r.os and b.dia > p_dia and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                      and b.presenca = 'turno') then
      v_ult := v_ult || jsonb_build_array(jsonb_build_object('os', r.os, 'bem', public._agenda_bem_da_os(r.os), 'cliente', r.cliente,
                                                             'sobra', to_jsonb(v_sobra)));
    end if;
    if (public.os_prontidao(r.os, p_hoje) ->> 'prazo_efetivo')::date = p_dia then
      v_prz := v_prz || jsonb_build_array(jsonb_build_object('os', r.os, 'bem', public._agenda_bem_da_os(r.os), 'cliente', r.cliente,
                                                             'sobra', to_jsonb(v_sobra)));
    end if;
  end loop;

  -- Os itens do dia: uma vez por etapa, pela ordem (turno, início da OS, OS, posição); começa pelo 1º meio-dia do dia, termina pelo
  -- último; a linha que termina é a de quem responde e a do resultado.
  for x in
    select l.tarefa, min(l.o) as primeiro,
           (array_agg(l.it order by l.o))[1] as prim, (array_agg(l.it order by l.o desc))[1] as ult,
           array_agg((l.it ->> 'linha_id')::uuid order by l.o) filter (where l.it ->> 'linha_id' is not null) as linhas
      from (select (it2 ->> 'tarefa')::uuid as tarefa, it2,
                   row_number() over (order by it2 ->> 'turno' = 'tarde', (it2 ->> 'ini')::timestamptz, it2 ->> 'os',
                                               (it2 ->> 'posicao')::int) as o
              from jsonb_array_elements(v_lin) it2) l(tarefa, it, o)
     group by l.tarefa
     order by 2
  loop
    v_itens := v_itens || jsonb_build_array(jsonb_build_object(
      'n', jsonb_array_length(v_itens) + 1,
      'tarefa', x.tarefa,
      'os', x.prim ->> 'os',
      'cliente', x.prim ->> 'cliente',
      'turno', x.prim ->> 'turno',
      'texto', (select t.texto from public.os_tarefas t where t.id = x.tarefa),
      'final', (select t.chave = 'entrega' from public.os_tarefas t where t.id = x.tarefa),
      'comeca', coalesce((x.prim ->> 'comeca')::boolean, true),
      'termina', coalesce((x.ult ->> 'termina')::boolean, false),
      'linha_id', case when coalesce((x.ult ->> 'termina')::boolean, false) then x.ult -> 'linha_id' end,
      'linhas', to_jsonb(coalesce(x.linhas, '{}'::uuid[])),
      'responde', x.ult -> 'responde',
      'resultado', case when coalesce((x.ult ->> 'termina')::boolean, false) then x.ult -> 'resultado' end,
      'com_dono', coalesce((x.ult ->> 'com_dono')::boolean, false)
                  and (select t.chave = 'entrega' from public.os_tarefas t where t.id = x.tarefa)));
  end loop;
  v_nos := (select count(distinct i ->> 'os') from jsonb_array_elements(v_itens) i);
  v_resp := coalesce((select jsonb_agg(distinct i ->> 'os') from jsonb_array_elements(v_itens) i
                       where i ->> 'responde' = p_payee::text), '[]'::jsonb);
  return jsonb_build_object(
    'modo', cf.modo_tarefas,
    'tem', jsonb_array_length(v_itens) > 0,
    'duas_os', v_nos > 1,
    'itens', v_itens,
    'pergunta', coalesce((select jsonb_agg(jsonb_build_object('n', (i ->> 'n')::int, 'texto', i ->> 'texto') order by (i ->> 'n')::int)
                            from jsonb_array_elements(v_itens) i
                           where (i ->> 'termina')::boolean and i ->> 'responde' = p_payee::text and i -> 'resultado' = 'null'::jsonb
                             and i ->> 'linha_id' is not null), '[]'::jsonb),
    'ultimo_dia', v_ult,
    'prazo', v_prz,
    'responde', v_resp);
end;
$function$;

comment on function public._agenda_tarefas_da_pessoa(uuid, date, date) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.2, §16.3.7): o dia da pessoa — {modo, tem, duas_os, itens [{n, tarefa, os, cliente, turno, texto, final, comeca, termina, linha_id (a linha que termina), linhas, responde, resultado, com_dono}], pergunta [{n, texto}] (o que termina no dia, de que ela responde, ainda sem resultado), ultimo_dia [{os, bem, cliente, sobra}] (as OS sem meio-dia vigente de turno depois do dia), prazo [{os, bem, cliente, sobra}] (as OS cujo prazo efetivo é o dia), responde [os]}. Para cada OS em que ela tem alocação vigente de turno no dia: de hoje em diante, o planejar de hoje (os meios-dias congelados com as linhas deles; os outros calculados); antes de hoje, as linhas congeladas do modo de agora. O item n: uma vez por etapa, pela ordem (turno, início da OS no dia, OS, posição) — estável: o "faltou a 2" da noite casa com o "2)" das 17:00. modo_tarefas desligado = {tem: false}. Com login, só admin/financeiro (42501); sem login, só o service_role. STABLE; definer (a spec dizia "sem grant; lida por definer": agenda_dia_da_pessoa e a linha do fechamento, invoker, a chamam); authenticated e service_role.';

-- O congelamento (§16.3.7): as linhas planejadas de um (OS, dia, turno) uma vez — as de amanhã no 1º tique com hora >= equipe_hora_ficha
-- (antes da ficha das 19:30), as de hoje no 1º tique do dia em que ainda não existem; o meio-dia congelado que perdeu a alocação, cancelada.
create or replace function public._agenda_tarefas_congelar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_modo  text;
  v_am    date;
  v_dias  date[];
  v_d     date;
  r       record;
  v_p     jsonb;
  v_meio  jsonb;
  it      jsonb;
  v_cong  int := 0;
  v_canc  int := 0;
  v_n     int;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora para congelar o plano das etapas.' using errcode = '22023';
  end if;
  v_modo := cf.modo_tarefas;
  if v_modo = 'desligado' then
    return jsonb_build_object('congelados', 0, 'cancelados', 0);
  end if;
  v_am := public.agenda_somar_du(p_hoje, 1);
  v_dias := array[p_hoje] || case when (p_agora at time zone 'America/Sao_Paulo')::time >= cf.equipe_hora_ficha then array[v_am]
                                  else '{}'::date[] end;

  -- o meio-dia congelado (de hoje em diante) que perdeu todas as alocações vigentes de turno: cancelada; as etapas voltam à fila
  update public.os_tarefas_dia d
     set estado = 'cancelada', cancelada_em = p_agora
   where d.estado = 'planejada' and d.modo = v_modo and d.dia >= p_hoje
     and not exists (select 1 from public.agenda_alocacoes a
                      where a.service_order_id = d.service_order_id and a.dia = d.dia and a.turno = d.turno
                        and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno');
  get diagnostics v_canc = row_count;

  foreach v_d in array v_dias loop
    for r in
      select a.service_order_id as os, array_agg(distinct a.turno) as turnos
        from public.agenda_alocacoes a
       where a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
         and exists (select 1 from public.os_tarefas t where t.service_order_id = a.service_order_id and t.estado = 'viva')
       group by a.service_order_id
       order by a.service_order_id
    loop
      continue when not exists (select 1 from unnest(r.turnos) tu
                                 where not exists (select 1 from public.os_tarefas_dia d
                                                    where d.service_order_id = r.os and d.dia = v_d and d.turno = tu and d.modo = v_modo
                                                      and d.estado = 'planejada'));
      v_p := public._agenda_tarefas_planejar(r.os, p_hoje, v_modo);
      for v_meio in select m from jsonb_array_elements(v_p -> 'meios') m
                     where (m ->> 'dia')::date = v_d and not (m ->> 'congelado')::boolean loop
        for it in select i from jsonb_array_elements(v_meio -> 'itens') i loop
          insert into public.os_tarefas_dia (tarefa_id, service_order_id, dia, turno, modo, fracao, comeca, termina, posicao, equipe,
                                             responde, estado, congelada_em)
          values ((it ->> 'tarefa')::uuid, r.os, v_d, v_meio ->> 'turno', v_modo, (it ->> 'fracao')::numeric,
                  (it ->> 'comeca')::boolean, (it ->> 'termina')::boolean, (it ->> 'posicao')::smallint,
                  array(select u::uuid from jsonb_array_elements_text(v_meio -> 'equipe') u), (v_meio ->> 'responde')::uuid,
                  'planejada', p_agora)
          on conflict do nothing;
          get diagnostics v_n = row_count;
          v_cong := v_cong + v_n;
        end loop;
      end loop;
    end loop;
  end loop;
  return jsonb_build_object('congelados', v_cong, 'cancelados', v_canc, 'dias', to_jsonb(v_dias));
end;
$function$;

comment on function public._agenda_tarefas_congelar(date, timestamptz) is
  'Agenda de Produção (Fase 7c, P8; spec §16.3.7, §16.5.2): o congelamento do plano do dia — para cada OS com etapa viva e alocação vigente de turno hoje (o 1º tique do dia em que o meio-dia ainda não tem linhas) ou no próximo dia útil (no 1º tique com hora >= equipe_hora_ficha, antes da ficha das 19:30), grava as linhas planejadas dos meios-dias que ainda não as têm (o planejar de hoje, no modo de agora; congelada_em = p_agora), uma vez por (etapa, dia, turno, modo). O meio-dia congelado de hoje em diante que perdeu todas as alocações vigentes de turno vira cancelada (as etapas voltam à fila). Sombra e ligado nunca se misturam. {congelados, cancelados, dias}. Definer, sem grant.';

-- A ÚNICA escrita de resultado (§16.5.2): a palavra do dono vale sobre todas; a da equipe, sobre a conferência e o roteiro; a conferência,
-- o roteiro e o sem registro só onde não há resultado. Na etapa: feita → feita; pendente → mais um dia pendente (e de feita de volta a viva);
-- sem registro → nada (conta como feita para o plano).
create or replace function public._agenda_tarefas_registrar(p_linhas uuid[], p_resultado text, p_via text, p_trecho text,
                                                           p_mensagem uuid, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  l       record;
  t       public.os_tarefas%rowtype;
  v_feit  int := 0;
  v_pend  int := 0;
  v_alert uuid[] := '{}';
begin
  if p_resultado is null or p_resultado not in ('feita', 'pendente', 'sem_registro') then
    raise exception 'Resultado de etapa desconhecido: "%" (feita, pendente ou sem_registro).', coalesce(p_resultado, '') using errcode = '22023';
  end if;
  if p_via is null or p_via not in ('equipe', 'dono', 'conferencia', 'roteiro') then
    raise exception 'Caminho desconhecido para anotar a etapa: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  for l in
    select d.* from public.os_tarefas_dia d
     where d.id = any (coalesce(p_linhas, '{}'::uuid[])) and d.estado = 'planejada' and d.termina
       and (d.resultado is null
            or p_via = 'dono'
            or (p_via = 'equipe' and d.resultado_via <> 'dono'))
       and not (p_resultado = 'sem_registro' and d.resultado is not null)
     order by d.dia, d.turno = 'tarde', d.posicao, d.id
  loop
    update public.os_tarefas_dia
       set resultado = p_resultado, resultado_via = p_via, resultado_em = p_agora,
           resultado_trecho = left(nullif(btrim(coalesce(p_trecho, '')), ''), 500), mensagem_id = coalesce(p_mensagem, mensagem_id)
     where id = l.id;
    select * into t from public.os_tarefas x where x.id = l.tarefa_id for update;
    continue when not found;
    if p_resultado = 'feita' then
      if t.estado = 'viva' then
        update public.os_tarefas
           set estado = 'feita', feita_em = p_agora, feita_via = p_via, pendente_vezes = 0, pendente_desde = null, pendente_ultimo = null,
               mudou_em = p_agora
         where id = t.id;
      end if;
      v_feit := v_feit + 1;
    elsif p_resultado = 'pendente' then
      if t.estado = 'feita' then
        update public.os_tarefas set estado = 'viva', feita_em = null, feita_via = null, mudou_em = p_agora where id = t.id;
        t.estado := 'viva';
      end if;
      if t.estado = 'viva' and t.pendente_ultimo is distinct from l.dia then
        update public.os_tarefas
           set pendente_vezes = t.pendente_vezes + 1, pendente_desde = coalesce(t.pendente_desde, l.dia), pendente_ultimo = l.dia,
               mudou_em = p_agora
         where id = t.id;
        if t.pendente_vezes + 1 >= cf.tarefas_pendente_alerta and not (t.id = any (v_alert)) then
          v_alert := v_alert || t.id;
        end if;
      end if;
      v_pend := v_pend + 1;
    end if;
  end loop;
  return jsonb_build_object('feitas', v_feit, 'pendentes', v_pend, 'alerta', to_jsonb(v_alert));
end;
$function$;

comment on function public._agenda_tarefas_registrar(uuid[], text, text, text, uuid, timestamptz) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.2): a única escrita de resultado das etapas — nas linhas planejadas que terminam: a do dono por cima de todas, a da equipe por cima da conferência e do roteiro, a conferência, o roteiro e o sem_registro só onde não há resultado. Em os_tarefas: feita → estado feita (feita_*, o pendente zerado); pendente → de feita volta a viva e soma 1 em pendente_vezes quando o dia é outro (pendente_desde no 1º, pendente_ultimo = o dia); sem_registro → nada (conta como feita para o plano, R5.2-3). {feitas, pendentes, alerta [tarefa]} (as que chegaram a tarefas_pendente_alerta). Definer, sem grant.';

-- A conferência (§16.5.2, R5.2-3): o resultado do meio-dia (pela conferência do dono ou pela resposta da equipe nas alocações) decide as
-- etapas que terminavam nele e ainda não têm resultado; sem resultado depois de tarefas_sem_registro_du dia útil, sem registro; o *desfaz*
-- da conferência refaz; com roteiro, os passos todos feitos fazem a etapa.
create or replace function public._agenda_tarefas_conferir(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_modo  text;
  r       record;
  v_r     jsonb;
  v_feit  int := 0;
  v_pend  int := 0;
  v_sem   int := 0;
  v_refe  int := 0;
  v_rot   int := 0;
  v_alert jsonb := '[]'::jsonb;
  v_os    uuid[] := '{}';
  v_ids   uuid[];
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora para conferir as etapas.' using errcode = '22023';
  end if;
  v_modo := cf.modo_tarefas;
  if v_modo = 'desligado' then
    return jsonb_build_object('feitas', 0, 'pendentes', 0, 'sem_registro', 0, 'refeitas', 0, 'pelo_roteiro', 0, 'os', '[]'::jsonb);
  end if;

  -- (3) a conferência desfeita ou mudada: a linha via conferência cujo meio-dia não diz mais o mesmo volta a sem resultado (e a etapa feita
  -- pela conferência volta a viva); a regra (1), logo abaixo, a refaz pelo resultado de agora.
  for r in
    select d.id, d.tarefa_id, d.service_order_id, d.resultado,
           (select case when count(*) = 0 or bool_or(a.resultado is null) then null
                        when bool_or(a.resultado in ('parcial', 'nao_cumprido')) then 'pendente'
                        when bool_and(a.resultado = 'cumprido') then 'feita' end
              from public.agenda_alocacoes a
             where a.service_order_id = d.service_order_id and a.dia = d.dia and a.turno = d.turno and a.presenca = 'turno'
               and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')) as agora
      from public.os_tarefas_dia d
     where d.estado = 'planejada' and d.modo = v_modo and d.termina and d.resultado_via = 'conferencia'
       and d.resultado in ('feita', 'pendente') and d.dia <= p_hoje
  loop
    continue when r.agora is not distinct from r.resultado;
    update public.os_tarefas_dia set resultado = null, resultado_via = null, resultado_em = null, resultado_trecho = null where id = r.id;
    update public.os_tarefas set estado = 'viva', feita_em = null, feita_via = null, mudou_em = p_agora
     where id = r.tarefa_id and estado = 'feita' and feita_via = 'conferencia';
    v_refe := v_refe + 1;
    v_os := v_os || r.service_order_id;
  end loop;

  -- (1) o meio-dia com resultado: algum parcial ou não cumprido → pendente; todos cumpridos → feita (via conferência)
  for r in
    select x.agora, array_agg(x.id order by x.id) as ids, array_agg(distinct x.service_order_id) as oss
      from (select d.id, d.service_order_id,
                   (select case when count(*) = 0 or bool_or(a.resultado is null) then null
                                when bool_or(a.resultado in ('parcial', 'nao_cumprido')) then 'pendente'
                                when bool_and(a.resultado = 'cumprido') then 'feita' end
                      from public.agenda_alocacoes a
                     where a.service_order_id = d.service_order_id and a.dia = d.dia and a.turno = d.turno and a.presenca = 'turno'
                       and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')) as agora
              from public.os_tarefas_dia d
             where d.estado = 'planejada' and d.modo = v_modo and d.termina and d.resultado is null and d.dia <= p_hoje) x
     where x.agora is not null
     group by x.agora
  loop
    v_r := public._agenda_tarefas_registrar(r.ids, r.agora, 'conferencia', null, null, p_agora);
    v_feit := v_feit + (v_r ->> 'feitas')::int;
    v_pend := v_pend + (v_r ->> 'pendentes')::int;
    v_alert := v_alert || coalesce(v_r -> 'alerta', '[]'::jsonb);
    v_os := v_os || r.oss;
  end loop;

  -- (2) sem resultado depois de tarefas_sem_registro_du dia útil: sem registro (conta como feita para o plano; "sem confirmação")
  v_ids := array(select d.id from public.os_tarefas_dia d
                  where d.estado = 'planejada' and d.modo = v_modo and d.termina and d.resultado is null
                    and public.agenda_somar_du(d.dia, cf.tarefas_sem_registro_du) <= p_hoje and d.dia < p_hoje);
  if cardinality(v_ids) > 0 then
    v_r := public._agenda_tarefas_registrar(v_ids, 'sem_registro', 'conferencia', null, null, p_agora);
    v_sem := cardinality(v_ids);
    v_os := v_os || array(select distinct d.service_order_id from public.os_tarefas_dia d where d.id = any (v_ids));
  end if;

  -- (4) com roteiro: a etapa viva cujos passos estão todos feitos (done; o "não se aplica" não conta como feito, mas não segura) é feita
  -- pelo roteiro, e as linhas dela que terminam e não têm resultado também
  for r in
    select t.id, t.service_order_id from public.os_tarefas t
     where t.estado = 'viva' and cardinality(t.passos) > 0
       and not exists (select 1 from public.service_order_steps st
                        where st.id = any (t.passos) and st.status not in ('done', 'not_applicable'))
       and exists (select 1 from public.service_order_steps st where st.id = any (t.passos) and st.status = 'done')
  loop
    update public.os_tarefas
       set estado = 'feita', feita_em = p_agora, feita_via = 'roteiro', pendente_vezes = 0, pendente_desde = null, pendente_ultimo = null,
           mudou_em = p_agora
     where id = r.id;
    perform public._agenda_tarefas_registrar(array(select d.id from public.os_tarefas_dia d
                                                     where d.tarefa_id = r.id and d.estado = 'planejada' and d.termina and d.resultado is null),
                                            'feita', 'roteiro', null, null, p_agora);
    v_rot := v_rot + 1;
    v_os := v_os || r.service_order_id;
  end loop;

  return jsonb_build_object('feitas', v_feit, 'pendentes', v_pend, 'sem_registro', v_sem, 'refeitas', v_refe, 'pelo_roteiro', v_rot,
                            'alerta', v_alert, 'os', to_jsonb(array(select distinct x from unnest(v_os) x)));
end;
$function$;

comment on function public._agenda_tarefas_conferir(date, timestamptz) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.2; R5.2-3): a conferência das etapas no modo de agora — (3) a linha via conferência cujo meio-dia não diz mais o mesmo (o *desfaz* da conferência) volta a sem resultado (a etapa feita pela conferência volta a viva) e é refeita por (1); (1) as linhas que terminam, sem resultado, de dia <= hoje, cujas alocações de turno do meio-dia têm resultado: algum parcial ou não cumprido → pendente, todos cumpridos → feita, via conferencia (por _agenda_tarefas_registrar: a palavra da equipe e a do dono valem sobre a conferência); (2) sem resultado depois de tarefas_sem_registro_du dia útil → sem_registro (conta como feita para o plano: não volta à fila, não soma pendente, não cria "não cabe" nem segura a conclusão; "sem confirmação" nas leituras); (4) com roteiro, a etapa viva cujos passos estão todos done (ou não se aplica, com algum done) → feita via roteiro, e as linhas dela sem resultado também. {feitas, pendentes, sem_registro, refeitas, pelo_roteiro, alerta, os}. Definer, sem grant.';

-- A leitura das etapas na resposta ao "como foi" (§16.3.8), sem IA: o texto e a lista perguntada ([{n, texto}]).
create or replace function public._agenda_ler_tarefas_da_resposta(p_texto text, p_lista jsonb)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  c_f     constant text := '\m(falt[a-z]*|nao (fiz|fizemos|deu|terminei|terminou|terminamos|acabei|acabou|consegui|conseguimos|vou conseguir)|ficou (pra|para) amanha|pendente|ainda nao|menos|exceto)\M';
  c_p     constant text := '\m(fiz|fizemos|feit[oa]s?|terminei|terminamos|terminad[oa]s?|acabei|acabamos|pront[oa]s?)\M';
  c_tudo  constant text := '\m(tudo|todas|todos|td|tds)\M';
  c_fora  constant text[] := array['terminar', 'acabar', 'fazer', 'pra', 'para', 'falta', 'faltou', 'faltaram', 'faltam', 'ficou',
                                   'amanha', 'ainda', 'menos', 'exceto', 'pendente', 'consegui', 'conseguimos', 'conseguiu', 'deu',
                                   'terminei', 'terminou', 'terminamos', 'acabei', 'acabou', 'acabamos', 'fizemos'];
  t       text := btrim(regexp_replace(regexp_replace(
                   translate(lower(coalesce(p_texto, '')), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc'),
                   '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'));
  v_g     jsonb := public._agenda_ler_resposta_da_equipe(p_texto);
  v_ns    int[];
  v_todos int[];
  v_f     boolean;
  v_p     boolean;
  v_tudo  boolean;
  v_depois text;
  v_pal   text[];
  v_cas   int[];
  v_mot   text;
  v_w     text[];
  k       int;
begin
  v_todos := array(select (i ->> 'n')::int from jsonb_array_elements(coalesce(p_lista, '[]'::jsonb)) i order by 1);
  if cardinality(v_todos) = 0 then
    return jsonb_build_object('entendeu', false, 'tudo', false, 'feitas', '[]'::jsonb, 'pendentes', '[]'::jsonb, 'fonte', 'nada',
                              'falou_de_falta', false, 'motivo', null);
  end if;
  v_f := t ~ c_f;
  v_p := t ~ c_p;
  v_tudo := t ~ c_tudo;
  v_ns := array(select distinct m[1]::int from regexp_matches(t, '\m([0-9]{1,2})\M', 'g') m order by 1);

  -- o motivo: a 1ª palavra ou par de palavras depois da falta que _agenda_motivo_dito reconhece; senão estimativa
  if v_f then
    v_depois := substr(t, (select position(m[1] in t) + char_length(m[1]) from regexp_matches(t, c_f) m limit 1));
    v_w := regexp_split_to_array(btrim(v_depois), ' ');
    for k in 1 .. coalesce(cardinality(v_w), 0) loop
      continue when v_w[k] ~ '^[0-9]+$' or v_w[k] = '';
      v_mot := coalesce(case when k < cardinality(v_w) then public._agenda_motivo_dito(v_w[k] || ' ' || v_w[k + 1]) end,
                        public._agenda_motivo_dito(v_w[k]));
      exit when v_mot is not null and v_mot <> 'equipe_faltou';
      v_mot := null;
    end loop;
  end if;
  v_mot := coalesce(v_mot, 'estimativa');

  if v_f then
    if cardinality(v_ns) > 0 then
      if not (v_ns <@ v_todos) then
        return jsonb_build_object('entendeu', false, 'tudo', false, 'feitas', '[]'::jsonb, 'pendentes', '[]'::jsonb, 'fonte', 'numeros',
                                  'falou_de_falta', true, 'motivo', 'numero_fora');
      end if;
      return jsonb_build_object('entendeu', true, 'tudo', false,
                                'feitas', to_jsonb(array(select x from unnest(v_todos) x where not (x = any (v_ns)) order by 1)),
                                'pendentes', to_jsonb(v_ns), 'fonte', 'numeros', 'falou_de_falta', true, 'motivo', v_mot);
    end if;
    -- as palavras ditas depois da falta (4 letras ou mais, fora as do próprio jeito de dizer) que casam UMA etapa só
    v_pal := array(select w from unnest(regexp_split_to_array(btrim(coalesce(v_depois, '')), ' ')) w
                    where char_length(w) >= 4 and not (w = any (c_fora)) and w !~ '^[0-9]+$');
    if cardinality(v_pal) > 0 then
      v_cas := array(select (i ->> 'n')::int from jsonb_array_elements(p_lista) i
                      where not exists (select 1 from unnest(v_pal) w
                                         where not (public._agenda_normal(i ->> 'texto') ~ ('\m' || w)))
                      order by 1);
      if cardinality(v_cas) = 1 then
        return jsonb_build_object('entendeu', true, 'tudo', false,
                                  'feitas', to_jsonb(array(select x from unnest(v_todos) x where x <> v_cas[1] order by 1)),
                                  'pendentes', to_jsonb(v_cas), 'fonte', 'palavras', 'falou_de_falta', true, 'motivo', v_mot);
      end if;
    end if;
    if cardinality(v_todos) = 1 then
      return jsonb_build_object('entendeu', true, 'tudo', false, 'feitas', '[]'::jsonb, 'pendentes', to_jsonb(v_todos), 'fonte', 'um_so',
                                'falou_de_falta', true, 'motivo', v_mot);
    end if;
    return jsonb_build_object('entendeu', false, 'tudo', false, 'feitas', '[]'::jsonb, 'pendentes', '[]'::jsonb, 'fonte', 'palavras',
                              'falou_de_falta', true, 'motivo', 'nao_entendi');
  end if;
  if v_p and cardinality(v_ns) > 0 then
    if not (v_ns <@ v_todos) then
      return jsonb_build_object('entendeu', false, 'tudo', false, 'feitas', '[]'::jsonb, 'pendentes', '[]'::jsonb, 'fonte', 'numeros',
                                'falou_de_falta', false, 'motivo', 'numero_fora');
    end if;
    return jsonb_build_object('entendeu', true, 'tudo', false, 'feitas', to_jsonb(v_ns),
                              'pendentes', to_jsonb(array(select x from unnest(v_todos) x where not (x = any (v_ns)) order by 1)),
                              'fonte', 'numeros', 'falou_de_falta', false, 'motivo', 'estimativa');
  end if;
  if v_tudo then
    return jsonb_build_object('entendeu', true, 'tudo', true, 'feitas', to_jsonb(v_todos), 'pendentes', '[]'::jsonb, 'fonte', 'tudo',
                              'falou_de_falta', false, 'motivo', null);
  end if;
  if v_g ->> 'tipo' = 'ok' then
    return jsonb_build_object('entendeu', true, 'tudo', false, 'feitas', to_jsonb(v_todos), 'pendentes', '[]'::jsonb, 'fonte', 'ok',
                              'falou_de_falta', false, 'motivo', null);
  end if;
  if cardinality(v_ns) > 0 and btrim(regexp_replace(t, '\m([0-9]{1,2}|e|a|o|as|os|so)\M', '', 'g')) = '' then
    return jsonb_build_object('entendeu', false, 'tudo', false, 'feitas', '[]'::jsonb, 'pendentes', '[]'::jsonb, 'fonte', 'numeros',
                              'falou_de_falta', false, 'motivo', 'so_numeros');
  end if;
  return jsonb_build_object('entendeu', false, 'tudo', false, 'feitas', '[]'::jsonb, 'pendentes', '[]'::jsonb, 'fonte', 'nada',
                            'falou_de_falta', false, 'motivo', null);
end;
$function$;

comment on function public._agenda_ler_tarefas_da_resposta(text, jsonb) is
  'Agenda de Produção (Fase 7c, P8; spec §16.3.8): a leitura das etapas na resposta ao "como foi", sem IA, pela lista perguntada [{n, texto}] (o que terminava hoje, de quem responde, sem resultado) — com falta (faltou, não fiz/deu/terminei/consegui…, ficou pra amanhã, pendente, ainda não, menos, exceto): os números = as pendentes ("ok, faltou a 2", "tudo certo menos o 3"; número fora da lista = não entendi), senão a única etapa cujo texto tem as palavras ditas depois da falta ("faltou o painel", "não deu pra terminar os cabo"), senão, com 1 item, ele; senão não entendi (falou_de_falta); com feito (fiz, feito, terminei, pronto…) e números: os números = as feitas ("fiz 1 e 3"); "tudo", "fiz tudo", "tudo feito", "todas" = todas feitas (tudo); o "ok" da gramática (só ok: "beleza", "foi tudo como o previsto") = todas feitas; só números ("1 e 3") = não entendi; o resto ("ok, só de manhã") = nada de etapa. {entendeu, tudo, feitas [n], pendentes [n], fonte (numeros | palavras | um_so | tudo | ok | nada), falou_de_falta, motivo (o código de _agenda_motivo_dito da 1ª palavra ou par depois da falta: "faltou peça" → material; senão estimativa)}. IMMUTABLE, sem grant.';

-- As datas de uma etapa pendente ("qua 04 e qui 05/11"; o mesmo dia: "qua 04/11"; meses diferentes: "sex 30/10 e seg 02/11").
create or replace function public._agenda_tarefa_datas(p_de date, p_ate date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_de is null then public._dia_curto(p_ate)
              when p_ate is null or p_de = p_ate then public._dia_curto(p_de)
              when extract(month from p_de) = extract(month from p_ate)
                then left(public._dia_curto(p_de), 3) || ' ' || to_char(p_de, 'DD') || ' e ' || public._dia_curto(p_ate)
              else public._dia_curto(p_de) || ' e ' || public._dia_curto(p_ate) end;
$function$;

comment on function public._agenda_tarefa_datas(date, date) is
  'Agenda de Produção (Fase 7c, P8): as datas de uma etapa pendente ao dono — "qua 04 e qui 05/11" (o mesmo mês), "qua 04/11" (um dia), "sex 30/10 e seg 02/11". IMMUTABLE; authenticated e service_role (os_tarefas_da_os a chama).';

-- As exceções ao dono (§16.3.9, §16.5.4): (a) a etapa pendente tarefas_pendente_alerta dias → UMA ação tarefa por sequência; (b) o que falta
-- não cabe até o prazo → a pergunta tarefa:prazo:<os>; (b') a etapa de risco sem quem faça → a pergunta tarefa:quem:<os>; as duas resolvidas
-- sozinhas quando voltam a caber. Em sombra, ação e pergunta em teste ("Em teste: ").
create or replace function public._agenda_tarefas_excecoes(p_hoje date, p_agora timestamptz, p_os uuid[] default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_modo  text;
  v_lig   boolean;
  v_dono  uuid := public._agenda_dono(null);
  v_pre   text;
  t       record;
  r       record;
  v_p     jsonb;
  v_prox  jsonb;
  v_quem  text;
  v_txt   text;
  v_cli   text;
  v_lst   text[];
  v_n     int;
  v_ids   uuid[];
  v_alert int := 0;
  v_nc    int := 0;
  v_sq    int := 0;
  v_res   int := 0;
  v_x     int;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora para as exceções das etapas.' using errcode = '22023';
  end if;
  v_modo := cf.modo_tarefas;
  if v_modo = 'desligado' then
    return jsonb_build_object('alertas', 0, 'nao_cabe', 0, 'sem_quem', 0, 'resolvidas', 0);
  end if;
  v_lig := v_modo = 'ligado';
  v_pre := case when v_lig then '' else 'Em teste: ' end;

  -- (a) pendente tarefas_pendente_alerta dias diferentes: UMA ação por sequência (antes {tarefa, desde, vezes})
  for t in
    select x.*, coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cli
      from public.os_tarefas x
      join public.service_orders so on so.id = x.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where x.estado = 'viva' and x.pendente_vezes >= cf.tarefas_pendente_alerta
       and (p_os is null or x.service_order_id = any (p_os))
       and not exists (select 1 from public.agenda_acoes a
                        where a.tipo = 'tarefa' and a.executada = v_lig and a.antes ->> 'tarefa' = x.id::text
                          and a.antes ->> 'desde' = x.pendente_desde::text)
     order by x.service_order_id, x.ordem
  loop
    v_p := public._agenda_tarefas_planejar(t.service_order_id, p_hoje, v_modo);
    select jsonb_build_object('dia', m ->> 'dia', 'posicao', (i ->> 'posicao')::int, 'primeiro',
                              (m ->> 'turno') = (select m2 ->> 'turno' from jsonb_array_elements(v_p -> 'meios') m2
                                                  where m2 ->> 'dia' = m ->> 'dia' order by m2 ->> 'turno' = 'tarde' limit 1))
      into v_prox
      from jsonb_array_elements(v_p -> 'meios') m, jsonb_array_elements(m -> 'itens') i
     where i ->> 'tarefa' = t.id::text and (m ->> 'dia')::date > coalesce(t.pendente_ultimo, p_hoje - 1)
     order by m ->> 'dia', m ->> 'turno' = 'tarde' limit 1;
    v_quem := public._agenda_lista(array(
      select public._agenda_nome_curto(py.name)
        from public.os_tarefas_dia d, unnest(d.equipe) u(pid) join public.payees py on py.id = u.pid
       where d.tarefa_id = t.id and d.resultado = 'pendente' and d.dia = t.pendente_ultimo and u.pid is distinct from v_dono
       group by py.name order by py.name), null);
    v_txt := format('%s: "%s" ficou faltando %s%s', t.cli, t.texto, public._agenda_tarefa_datas(t.pendente_desde, t.pendente_ultimo),
                    coalesce(' (' || nullif(v_quem, '') || ')', ''))
             || case when v_prox is not null
                     then format('. Passei para %s%s.', public._dia_curto((v_prox ->> 'dia')::date),
                                 case when (v_prox ->> 'posicao')::int = 1 and coalesce((v_prox ->> 'primeiro')::boolean, false)
                                      then ', no começo do dia' else '' end)
                     else format(' e não tem outro dia marcado no %s: me diga quando.', t.cli) end
             || format(' Se já está feita, me diga (ex.: "no %s, %s já está feita").', t.cli,
                       lower(left(t.texto, 1)) || substr(t.texto, 2));
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), p_hoje, v_lig, 'vigia', 'tarefa', t.service_order_id, array[t.service_order_id],
            jsonb_build_object('tarefa', t.id, 'desde', t.pendente_desde, 'vezes', t.pendente_vezes),
            jsonb_build_object('motivo', 'pendente', 'proximo', v_prox -> 'dia'),
            left(v_pre || v_txt, 400));
    v_alert := v_alert + 1;
  end loop;

  -- (b) e (b'): cada OS de compromisso (de p_os, ou todas): o que não cabe até o prazo e a etapa de risco sem quem faça
  for r in
    select x.os, coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cli
      from (select distinct a.service_order_id as os from public.agenda_alocacoes a
             where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno' and a.dia >= p_hoje
               and exists (select 1 from public.os_tarefas t2 where t2.service_order_id = a.service_order_id and t2.estado = 'viva')
            union
            select q.service_order_id from public.agenda_perguntas q
             where q.tipo = 'tarefa' and q.estado = 'aberta' and q.modo = v_modo and q.service_order_id is not null) x
      join public.service_orders so on so.id = x.os
      left join public.clients cl on cl.id = so.client_id
     where p_os is null or x.os = any (p_os)
     order by so.service_order_number, x.os
  loop
    v_p := public._agenda_tarefas_planejar(r.os, p_hoje, v_modo);
    -- (b) não cabe até o prazo
    if round(coalesce((v_p ->> 'sobra_no_prazo')::numeric, 0), 2) > 0 and (v_p ->> 'prazo')::date >= p_hoje then
      v_lst := array(select t2.texto from jsonb_array_elements_text(coalesce(v_p -> 'faltam', '[]'::jsonb)) with ordinality u(id, o)
                       join public.os_tarefas t2 on t2.id = u.id::uuid order by u.o);
      v_n := cardinality(v_lst);
      v_txt := format('%s: o que falta não cabe até o prazo, %s — %s (cerca de %s), e o plano %s até lá. Me diga como fica: chamar alguém junto, usar o sábado ou passar do prazo.',
                      r.cli, public._dia_curto((v_p ->> 'prazo')::date),
                      case when v_n > 4 then array_to_string(v_lst[1:4], ', ') || format(' e mais %s', v_n - 4)
                           else public._agenda_lista(v_lst, null) end,
                      public._agenda_dias(greatest(ceil((v_p ->> 'falta')::numeric), 1) / 2),
                      case when coalesce((v_p ->> 'meios_ate_prazo')::int, 0) = 0 then 'não tem mais nenhum dia'
                           else 'tem ' || public._agenda_dias((v_p ->> 'meios_ate_prazo')::numeric / 2) end);
      insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, modo, criada_em)
      values ('tarefa', 'tarefa:prazo:' || r.os, r.os, array[r.os], (v_p ->> 'prazo')::date, left(v_pre || v_txt, 600), '[]'::jsonb,
              v_modo, p_agora)
      on conflict (chave, modo) where estado = 'aberta' do nothing;
      get diagnostics v_x = row_count;
      v_nc := v_nc + v_x;
    else
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'coube'
       where tipo = 'tarefa' and chave = 'tarefa:prazo:' || r.os and modo = v_modo and estado = 'aberta';
      get diagnostics v_x = row_count;
      v_res := v_res + v_x;
    end if;
    -- (b') a etapa de risco que nenhum meio-dia marcado atende
    v_ids := array(select u::uuid from jsonb_array_elements_text(coalesce(v_p -> 'sem_quem', '[]'::jsonb)) u);
    if cardinality(v_ids) > 0 then
      select t2.* into t from public.os_tarefas t2 where t2.id = v_ids[1];
      v_lst := array(select public._agenda_nome_curto(py.name)
                       from (select distinct u.x::uuid as pid
                               from jsonb_array_elements(v_p -> 'meios') m, jsonb_array_elements_text(m -> 'equipe') u(x)
                              where not (m ->> 'congelado')::boolean) z
                       join public.payees py on py.id = z.pid
                      order by py.name);
      v_txt := format('%s: "%s" pede %s, e nos dias marcados %s. Quem vai junto?', r.cli, t.texto,
                      public._agenda_exigencia_texto(t.exige, null),
                      case when cardinality(v_lst) = 0 then 'não vai ninguém da equipe'
                           when cardinality(v_lst) = 1 then 'só vai o ' || v_lst[1]
                           else 'só vão ' || public._agenda_lista(array(select 'o ' || x from unnest(v_lst) x), null) end);
      insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, modo, criada_em)
      values ('tarefa', 'tarefa:quem:' || r.os, r.os, array[r.os], left(v_pre || v_txt, 600), '[]'::jsonb, v_modo, p_agora)
      on conflict (chave, modo) where estado = 'aberta' do nothing;
      get diagnostics v_x = row_count;
      v_sq := v_sq + v_x;
    else
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'agora tem quem faça'
       where tipo = 'tarefa' and chave = 'tarefa:quem:' || r.os and modo = v_modo and estado = 'aberta';
      get diagnostics v_x = row_count;
      v_res := v_res + v_x;
    end if;
  end loop;
  return jsonb_build_object('alertas', v_alert, 'nao_cabe', v_nc, 'sem_quem', v_sq, 'resolvidas', v_res);
end;
$function$;

comment on function public._agenda_tarefas_excecoes(date, timestamptz, uuid[]) is
  'Agenda de Produção (Fase 7c, P8; spec §16.3.9, §16.5.4, §16.6.5): as exceções ao dono — (a) a etapa viva pendente em tarefas_pendente_alerta dias diferentes: UMA ação tarefa por sequência (origem vigia, executada = ligado, sem *desfaz*, antes {tarefa, desde, vezes}), que entra sozinha no "o que mudou": "Lenine: "Passagem e crimpagem de cabos de bateria" ficou faltando qua 04 e qui 05/11 (Alex). Passei para sex 06/11, no começo do dia. Se já está feita, me diga (ex.: "no Lenine, passagem e crimpagem de cabos de bateria já está feita")." (sem outro dia: "… e não tem outro dia marcado no Lenine: me diga quando."); (b) para cada OS de compromisso (p_os, ou todas no passo diário), o que falta que não cabe até o prazo (o planejar: sobra_no_prazo): UMA pergunta tarefa:prazo:<os> (não crítica, sem opções, perda_em = o prazo) — "Flávio: o que falta não cabe até o prazo, sex 06/11 — …, … e … (cerca de 1,5 dia), e o plano tem 1 dia até lá. Me diga como fica: chamar alguém junto, usar o sábado ou passar do prazo."; resolvida "coube" quando volta a caber; (b'') a etapa de risco que nenhum meio-dia marcado atende: tarefa:quem:<os> — "Lenine: "Substituição baterias - chumbo para litio" pede quem instala sozinho com 220 V ou banco de bateria, e nos dias marcados só vai o Mateus. Quem vai junto?"; resolvida "agora tem quem faça". No modo de agora (em sombra, "Em teste: " e executada = false). {alertas, nao_cabe, sem_quem, resolvidas}. Definer, sem grant.';

-- A rodada das etapas (§16.5.4), a cada tique, o molde de agenda_aprender: sincronizar, congelar, conferir, as exceções do que mudou e, uma
-- vez por dia a partir de tarefas_hora, as exceções de todas as OS e, em teste, o que a ficha de amanhã diria.
create or replace function public.agenda_tarefas_rodar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config;
  v_t0     timestamptz := clock_timestamp();
  v_modo   text;
  v_ult    timestamptz;
  v_diario boolean;
  v_am     date;
  v_os     uuid[] := '{}';
  v_r      jsonb;
  v_cont   jsonb := '{}'::jsonb;
  v_erros  int := 0;
  v_falhas jsonb := '[]'::jsonb;
  v_estado text;
  v_msg    text;
  v_passo  text;
  v_fez    boolean := false;
  v_sinc   int := 0;
  v_mud    int := 0;
  x        record;
  v_tp     jsonb;
  v_txt    text;
  v_teste  int := 0;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada das etapas.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_tarefas'));
  cf := public._agenda_cfg();
  v_modo := cf.modo_tarefas;
  if v_modo = 'desligado' then
    return jsonb_build_object('rodou', false, 'modo', v_modo);
  end if;
  v_ult := (select max(vr.p_agora) from public.agenda_vigia_rodadas vr where vr.rotina = 'tarefas' and vr.p_agora < p_agora);
  v_diario := (p_agora at time zone 'America/Sao_Paulo')::time >= cf.tarefas_hora
              and not exists (select 1 from public.agenda_vigia_rodadas vr
                               where vr.rotina = 'tarefas' and vr.p_hoje = p_hoje and vr.contagens ? 'diario');
  v_am := public.agenda_somar_du(p_hoje, 1);

  -- 1. sincronizar: as OS com alocação vigente sem reserva de hoje a hoje + 14 ou em andamento
  v_passo := 'sincronizar';
  begin
    for x in
      select distinct so.id from public.service_orders so
       where (exists (select 1 from public.agenda_alocacoes a
                       where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                         and a.dia between p_hoje and p_hoje + 14)
              or so.status = 'in_progress')
         and so.status not in ('completed', 'invoiced', 'cancelled')
       order by so.id
    loop
      v_r := public._agenda_tarefas_sincronizar(x.id, p_hoje, p_agora);
      v_sinc := v_sinc + 1;
      if coalesce((v_r ->> 'mudou')::boolean, false) then
        v_mud := v_mud + 1;
        v_os := v_os || x.id;
      end if;
    end loop;
    v_cont := v_cont || jsonb_build_object('sincronizar', jsonb_build_object('os', v_sinc, 'mudaram', v_mud));
    v_fez := v_fez or v_mud > 0;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    v_erros := v_erros + 1;
    v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
    perform public.log_app_error('db', format('etapas do serviço, passo %s: %s', v_passo, v_msg), 'agenda', 'tarefas:' || v_passo,
                                 'error', jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
  end;

  -- 2. congelar e 3. conferir
  foreach v_passo in array array['congelar', 'conferir'] loop
    begin
      if v_passo = 'congelar' then
        v_r := public._agenda_tarefas_congelar(p_hoje, p_agora);
        v_fez := v_fez or (v_r ->> 'congelados')::int > 0 or (v_r ->> 'cancelados')::int > 0;
      else
        v_r := public._agenda_tarefas_conferir(p_hoje, p_agora);
        v_os := v_os || array(select u::uuid from jsonb_array_elements_text(coalesce(v_r -> 'os', '[]'::jsonb)) u);
        v_fez := v_fez or jsonb_array_length(coalesce(v_r -> 'os', '[]'::jsonb)) > 0;
      end if;
      v_cont := v_cont || jsonb_build_object(v_passo, v_r);
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('etapas do serviço, passo %s: %s', v_passo, v_msg), 'agenda', 'tarefas:' || v_passo,
                                   'error', jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;

  -- 4. as exceções das OS que mudaram neste tique (as sincronizadas, as conferidas e as respondidas desde a rodada anterior)
  v_passo := 'excecoes';
  begin
    v_os := v_os || array(select distinct d.service_order_id from public.os_tarefas_dia d
                           where d.resultado_em > coalesce(v_ult, p_agora - interval '1 day') and d.resultado_em <= p_agora);
    v_os := array(select distinct u from unnest(v_os) u where u is not null);
    if cardinality(v_os) > 0 then
      v_r := public._agenda_tarefas_excecoes(p_hoje, p_agora, v_os);
      v_cont := v_cont || jsonb_build_object('excecoes', v_r);
      v_fez := true;
    end if;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    v_erros := v_erros + 1;
    v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
    perform public.log_app_error('db', format('etapas do serviço, passo %s: %s', v_passo, v_msg), 'agenda', 'tarefas:' || v_passo,
                                 'error', jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
  end;

  -- 5. o passo diário (uma vez por dia, a partir de tarefas_hora): as exceções de todas as OS de compromisso e, em teste, o que a ficha de
  -- amanhã diria a quem responde (até 2 ações de teste; sem repetir no dia)
  if v_diario then
    v_passo := 'diario';
    begin
      v_r := public._agenda_tarefas_excecoes(p_hoje, p_agora, null);
      if v_modo = 'sombra' then
        for x in
          select c.payee_id, public._agenda_nome_curto(py.name) as nome
            from public._agenda_contatos_com_plano(v_am) c(payee_id) join public.payees py on py.id = c.payee_id
           order by py.name, c.payee_id
        loop
          exit when v_teste >= 2;
          v_tp := public._agenda_tarefas_da_pessoa(x.payee_id, v_am, p_hoje);
          continue when not coalesce((v_tp ->> 'tem')::boolean, false) or jsonb_array_length(coalesce(v_tp -> 'responde', '[]'::jsonb)) = 0;
          continue when exists (select 1 from public.agenda_acoes a
                                 where a.tipo = 'tarefa' and not a.executada and a.dia = p_hoje
                                   and a.antes ->> 'chave' = format('teste:%s:%s', x.payee_id, v_am));
          v_txt := format('Em teste (o que cada um faz): %s o %s levaria na ficha: %s. Às %s eu perguntaria o que ficou faltando.',
                          case when v_am = p_hoje + 1 then 'amanhã (' || public._dia_curto(v_am) || ')' else public._dia_curto(v_am) end,
                          x.nome,
                          public._agenda_tarefas_lista_texto(
                            (select jsonb_agg(i || jsonb_build_object('com', case when (i ->> 'com_dono')::boolean
                                                                                  then 'o ' || coalesce((select public._agenda_nome_curto(p.name) from public.payees p where p.id = public._agenda_dono(null)), 'responsável') end,
                                                                      'rotulo', case when (v_tp ->> 'duas_os')::boolean then i ->> 'cliente' end)
                                              order by (i ->> 'n')::int)
                               from jsonb_array_elements(v_tp -> 'itens') i),
                            cf.tarefas_linhas_max, 300),
                          to_char(cf.equipe_hora_como_foi, 'HH24:MI'));
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, service_order_id, os_ids, antes, depois, texto)
          values (clock_timestamp(), p_hoje, false, 'vigia', 'tarefa', x.payee_id,
                  (v_tp -> 'itens' -> 0 ->> 'os')::uuid,
                  array(select distinct (i ->> 'os')::uuid from jsonb_array_elements(v_tp -> 'itens') i),
                  jsonb_build_object('chave', format('teste:%s:%s', x.payee_id, v_am), 'dia', v_am),
                  jsonb_build_object('motivo', 'teste'), left(v_txt, 400));
          v_teste := v_teste + 1;
        end loop;
      end if;
      v_cont := v_cont || jsonb_build_object('diario', v_r || jsonb_build_object('teste', v_teste));
      v_fez := true;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      v_cont := v_cont || jsonb_build_object('diario', jsonb_build_object('falhou', true));
      perform public.log_app_error('db', format('etapas do serviço, passo %s: %s', v_passo, v_msg), 'agenda', 'tarefas:' || v_passo,
                                   'error', jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end if;

  -- A linha da rotina: quando algum passo fez algo, falhou, ou no passo diário (não uma por tique vazio).
  if v_fez or v_erros > 0 or v_diario then
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                             rotina, modo_equipe, modo_diaria)
    values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
            v_cont || jsonb_build_object('modo', v_modo, 'falhas', v_falhas),
            least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
            'tarefas', cf.modo_equipe, cf.modo_diaria);
  end if;
  return jsonb_build_object('rodou', true, 'modo', v_modo, 'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas,
                            'gravou', v_fez or v_erros > 0 or v_diario);
end;
$function$;

comment on function public.agenda_tarefas_rodar(date, timestamptz) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.4): a rodada das etapas (o passo 0a do task-automations, a cada tique, antes da rotina da equipe; o molde de agenda_aprender) — com pg_advisory_xact_lock; modo_tarefas desligado = {rodou: false}. Cada passo no seu bloco (o que falha vai a log_app_error, context agenda, action tarefas:<passo>, e os outros seguem): sincronizar (as OS com alocação vigente sem reserva de hoje a hoje + 14 ou em andamento, pela assinatura), congelar, conferir, as exceções das OS que mudaram neste tique (sincronizadas, conferidas, respondidas desde a rodada anterior) e, uma vez por dia a partir de tarefas_hora, o diário: as exceções de todas as OS de compromisso e, em teste, até 2 ações tarefa executada = false com o que a ficha de amanhã diria a quem responde ("Em teste (o que cada um faz): amanhã (qui 05/11) o Alex levaria na ficha: 1) …. Às 17:00 eu perguntaria o que ficou faltando."). Grava agenda_vigia_rodadas (rotina tarefas) quando algum passo fez algo, falhou, ou no diário. {rodou, modo, contagens, erros, falhas, gravou}. Nenhuma mensagem a ninguém. Definer; só service_role.';

-- O feito × pendente da OS (§16.5.5, §16.6.8; R5.2-3: a sem registro aparece como "sem confirmação").
create or replace function public.os_tarefas_da_os(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config;
  v_uid   uuid := auth.uid();
  v_papel text;
  v_p     jsonb;
  v_et    jsonb := '[]'::jsonb;
  r       record;
  v_ult   record;
  v_est   text;
  v_qd    date;
  v_feit  text[] := '{}';
  v_falt  text[] := '{}';
  v_tot   int := 0;
  v_cab   text;
  v_nc    text;
  v_txt   text;
  v_k     int;
  v_cabe  boolean;
begin
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'As etapas da OS são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'As etapas da OS são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  cf := public._agenda_cfg();
  if p_os is null or not exists (select 1 from public.service_orders so where so.id = p_os) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  if cf.modo_tarefas = 'desligado'
     or not exists (select 1 from public.os_tarefas t where t.service_order_id = p_os and t.estado in ('viva', 'feita', 'nao_se_aplica')) then
    return jsonb_build_object('ok', true, 'modo', cf.modo_tarefas, 'etapas', '[]'::jsonb, 'feitas', 0, 'faltam', 0, 'texto', null);
  end if;
  v_p := public._agenda_tarefas_planejar(p_os, p_hoje, cf.modo_tarefas);
  for r in select t.* from public.os_tarefas t
            where t.service_order_id = p_os and t.estado in ('viva', 'feita', 'nao_se_aplica') order by t.ordem, t.id loop
    select d.resultado, d.dia, d.turno into v_ult from public.os_tarefas_dia d
     where d.tarefa_id = r.id and d.modo = cf.modo_tarefas and d.estado = 'planejada' and d.termina and d.resultado is not null
     order by d.dia desc, d.turno = 'tarde' desc, d.resultado_em desc limit 1;
    v_est := case when r.estado = 'feita' then 'feita' when r.estado = 'nao_se_aplica' then 'nao_se_aplica'
                  when v_ult.resultado = 'pendente' then 'pendente' when v_ult.resultado = 'sem_registro' then 'sem_confirmacao'
                  else 'falta' end;
    -- quando: o 1º meio-dia dela depois do último que já tem resultado (o pendente de hoje vai ao próximo)
    v_qd := (select (m ->> 'dia')::date from jsonb_array_elements(v_p -> 'meios') m, jsonb_array_elements(m -> 'itens') i
              where i ->> 'tarefa' = r.id::text
                and (v_ult.dia is null
                     or ((m ->> 'dia')::date, (m ->> 'turno') = 'tarde') > (v_ult.dia, v_ult.turno = 'tarde'))
              order by m ->> 'dia', m ->> 'turno' = 'tarde' limit 1);
    v_et := v_et || jsonb_build_array(jsonb_build_object(
      'n', jsonb_array_length(v_et) + 1, 'tarefa', r.id, 'texto', r.texto, 'estado', v_est, 'quando', v_qd, 'feita_em', r.feita_em,
      'feita_via', r.feita_via, 'pendente_vezes', r.pendente_vezes, 'pendente_desde', r.pendente_desde,
      'nova_no_escopo', r.nova_no_escopo, 'exige_texto', public._agenda_exigencia_texto(r.exige, null)));
    if v_est = 'feita' then
      v_feit := v_feit || r.texto;
      v_tot := v_tot + 1;
    elsif v_est <> 'nao_se_aplica' then
      v_tot := v_tot + 1;
      v_falt := v_falt || (r.texto || coalesce(' (' || case
        when v_est = 'pendente' then 'ficou faltando ' || public._agenda_tarefa_datas(r.pendente_desde, coalesce(r.pendente_ultimo, v_ult.dia))
                                     || coalesce('; vai ' || public._dia_curto(v_qd), '')
        when v_est = 'sem_confirmacao' then 'sem confirmação'
        when r.nova_no_escopo then 'entrou ' || public._dia_curto((r.criada_em at time zone 'America/Sao_Paulo')::date)
                                   || case when r.origem = 'dono' then ': você disse' else ': o orçamento aumentou' end
        else public._dia_curto(v_qd) end || ')', ''));
    end if;
  end loop;

  v_cabe := round(coalesce((v_p ->> 'sobra_no_prazo')::numeric, 0), 2) <= 0;
  v_cab := case when cf.modo_tarefas = 'ligado' then 'Etapas: ' else 'Etapas (em teste: a equipe ainda não recebe): ' end;
  v_nc := case when not v_cabe and v_p ->> 'prazo' is not null
               then format(' Até %s não cabe: falta cerca de %s e o plano %s.', public._dia_curto((v_p ->> 'prazo')::date),
                           public._agenda_dias(greatest(ceil((v_p ->> 'falta')::numeric), 1) / 2),
                           case when coalesce((v_p ->> 'meios_ate_prazo')::int, 0) = 0 then 'não tem mais dia até lá'
                                else 'tem ' || replace(trim_scale((v_p ->> 'meios_ate_prazo')::numeric / 2)::text, '.', ',') end) end;
  if cardinality(v_falt) = 0 then
    v_txt := v_cab || case when v_tot = 1 then 'a única feita.' else format('as %s feitas.', v_tot) end;
  else
    v_k := least(cardinality(v_falt), 3);
    loop
      v_txt := v_cab || format('%s de %s feitas', cardinality(v_feit), v_tot)
               || case when cardinality(v_feit) between 1 and 2 and v_k = least(cardinality(v_falt), 3)
                       then ' (' || public._agenda_lista(v_feit, null) || ')' else '' end
               || '. Falta: ' || array_to_string(v_falt[1:v_k], '; ')
               || case when cardinality(v_falt) > v_k then format('; e mais %s', cardinality(v_falt) - v_k) else '' end || '.'
               || coalesce(v_nc, '');
      exit when char_length(v_txt) <= 400 or v_k = 1;
      v_k := v_k - 1;
    end loop;
    v_txt := public._agenda_corta(v_txt, 400);
  end if;
  return jsonb_build_object('ok', true, 'modo', cf.modo_tarefas, 'etapas', v_et, 'feitas', cardinality(v_feit),
                            'faltam', v_tot - cardinality(v_feit), 'falta_meios', (v_p ->> 'falta')::numeric,
                            'prazo', v_p -> 'prazo', 'cabe', v_cabe, 'texto', v_txt);
end;
$function$;

comment on function public.os_tarefas_da_os(uuid, date) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.5, §16.6.8; R5.2-3): o feito × pendente da OS — {ok, modo, etapas [{n, tarefa, texto, estado (feita | falta | pendente | sem_confirmacao | nao_se_aplica), quando (o próximo dia planejado), feita_em, feita_via, pendente_vezes, pendente_desde, nova_no_escopo, exige_texto}], feitas, faltam, falta_meios, prazo, cabe, texto} — texto (≤ 400, a linha "Etapas" de _agenda_ver_os): "Etapas: 1 de 5 feitas (Diagnóstico de vazamento do sistema de água pressurizado). Falta: Conversão do sistema de refrigeração para 12V (sex 06/11); Substituição da tampa da boia (sex 06/11); Instalação do compressor e recarga de gás (entrou qua 04/11: o orçamento aumentou); e mais 1. Até sex 06/11 não cabe: falta cerca de 1,5 dia e o plano tem 1."; a pendente "(ficou faltando qua 04 e qui 05/11; vai sex 06/11)"; a sem registro "(sem confirmação)"; tudo feito "Etapas: as 4 feitas."; em teste "Etapas (em teste: a equipe ainda não recebe): …". modo_tarefas desligado ou sem etapa = texto nulo. Com login, só admin/financeiro (42501); sem login, só o service_role. STABLE; definer (a spec dizia invoker: o planejar não tem grant); authenticated e service_role.';

-- As medidas das etapas (§16.5.5, §16.11; R5.2-3).
create or replace function public.agenda_tarefas_medidas(p_de date, p_ate date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config;
  v_uid   uuid := auth.uid();
  v_papel text;
  v_dono  uuid := public._agenda_dono(null);
  v_n     jsonb;
  v_hab   jsonb := '{}'::jsonb;
  v_dalt  int;
  h       record;
  v_lin   record;
  v_risco int := 0;
  v_feit  int;
  v_pend  int;
  v_sem   int;
  v_plan  int;
  v_res   jsonb;
begin
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'As medidas das etapas são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'As medidas das etapas são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_de is null or p_ate is null or p_hoje is null then
    raise exception 'agenda_tarefas_medidas: p_de, p_ate e p_hoje são obrigatórios.' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_n := jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                            'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura, 'par', cf.habilidade_nivel_par);
  select count(*), count(*) filter (where d.resultado = 'feita'), count(*) filter (where d.resultado = 'pendente'),
         count(*) filter (where d.resultado = 'sem_registro')
    into v_plan, v_feit, v_pend, v_sem
    from public.os_tarefas_dia d
   where d.modo = 'ligado' and d.estado = 'planejada' and d.termina and d.dia between p_de and p_ate;

  -- a etapa de risco num meio-dia cuja equipe não atende pela regra de hoje (tem de ser 0)
  for h in select * from public.agenda_habilidades(p_hoje,
             array(select distinct u from public.os_tarefas_dia d, unnest(d.equipe) u
                    where d.estado = 'planejada' and d.dia between p_de and p_ate) || v_dono) loop
    v_hab := v_hab || jsonb_build_object(h.payee_id::text, jsonb_build_array(h.instala, h.comissiona, h.altura, h.papel));
    if h.eh_dono then
      v_dalt := h.altura;
    end if;
  end loop;
  for v_lin in
    select d.equipe, t.exige, t.chave = 'entrega' as fin,
           exists (select 1 from public.agenda_alocacoes a where a.service_order_id = d.service_order_id and a.dia = d.dia
                     and a.turno = d.turno and a.presenca = 'turno' and a.payee_id is not distinct from v_dono
                     and a.estado in ('publicada', 'fixada')) as dt,
           exists (select 1 from public.agenda_alocacoes a where a.service_order_id = d.service_order_id and a.dia = d.dia
                     and a.turno = d.turno and a.presenca = 'fechamento' and a.payee_id is not distinct from v_dono
                     and a.estado in ('publicada', 'fixada')) as df
      from public.os_tarefas_dia d join public.os_tarefas t on t.id = d.tarefa_id
     where d.modo = 'ligado' and d.estado = 'planejada' and d.dia between p_de and p_ate and t.exige <> 0
  loop
    if public._agenda_atende(case when v_lin.df and cf.habilidade_fechamento_cobre
                                  then case when v_lin.fin then 0 else v_lin.exige & ~10 end else v_lin.exige end,
         array(select (v_hab -> u::text ->> 0)::int from unnest(v_lin.equipe) with ordinality x(u, o) order by o),
         array(select (v_hab -> u::text ->> 1)::int from unnest(v_lin.equipe) with ordinality x(u, o) order by o),
         array(select (v_hab -> u::text ->> 2)::int from unnest(v_lin.equipe) with ordinality x(u, o) order by o),
         array(select (v_hab -> u::text ->> 3)::int from unnest(v_lin.equipe) with ordinality x(u, o) order by o),
         v_lin.dt, v_dalt, v_n) is not null then
      v_risco := v_risco + 1;
    end if;
  end loop;

  select jsonb_build_object(
           'com_lista', count(*) filter (where m.leitura ? 'lista'),
           'entendidas', count(*) filter (where coalesce((m.leitura #>> '{tarefas,entendeu}')::boolean, false)),
           'nao_entendidas', count(*) filter (where m.leitura ? 'lista' and not coalesce((m.leitura #>> '{tarefas,entendeu}')::boolean, false)))
    into v_res
    from public.agenda_equipe_mensagens m
   where m.tipo = 'como_foi' and m.modo = 'ligado' and m.dia between p_de and p_ate;

  return jsonb_build_object(
    'de', p_de, 'ate', p_ate,
    'planejadas', v_plan, 'feitas_no_dia', v_feit, 'pendentes', v_pend, 'sem_registro', v_sem,
    'ppc_etapas', case when v_feit + v_pend > 0 then round(v_feit::numeric / (v_feit + v_pend), 3) end,
    'alertas_2_dias', (select count(*) from public.agenda_acoes a
                        where a.tipo = 'tarefa' and a.executada and a.antes ? 'vezes' and a.dia between p_de and p_ate),
    'nao_cabe', (select count(*) from public.agenda_perguntas q
                  where q.tipo = 'tarefa' and q.modo = 'ligado' and q.chave like 'tarefa:prazo:%'
                    and (q.criada_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate),
    'sem_quem', (select count(*) from public.agenda_perguntas q
                  where q.tipo = 'tarefa' and q.modo = 'ligado' and q.chave like 'tarefa:quem:%'
                    and (q.criada_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate),
    'respostas', v_res,
    'escopo_novo', (select count(*) from public.os_tarefas t
                     where t.nova_no_escopo and (t.criada_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate),
    -- na conclusão (de um ou do outro): com alguma etapa viva cuja última linha que termina ficou pendente (dita), e só com sem registro
    'concluidas_com_pendencia', (select count(*) from public.service_orders so
       where (so.check_out_at at time zone 'America/Sao_Paulo')::date between p_de and p_ate
         and exists (select 1 from public.os_tarefas t
                      where t.service_order_id = so.id and t.estado = 'viva'
                        and (select d.resultado from public.os_tarefas_dia d
                              where d.tarefa_id = t.id and d.estado = 'planejada' and d.termina and d.resultado is not null
                              order by d.dia desc, d.turno = 'tarde' desc limit 1) = 'pendente')),
    'concluidas_sem_confirmacao', (select count(*) from public.service_orders so
       where (so.check_out_at at time zone 'America/Sao_Paulo')::date between p_de and p_ate
         and not exists (select 1 from public.os_tarefas t
                          where t.service_order_id = so.id and t.estado = 'viva'
                            and (select d.resultado from public.os_tarefas_dia d
                                  where d.tarefa_id = t.id and d.estado = 'planejada' and d.termina and d.resultado is not null
                                  order by d.dia desc, d.turno = 'tarde' desc limit 1) = 'pendente')
         and exists (select 1 from public.os_tarefas t
                      where t.service_order_id = so.id and t.estado = 'viva'
                        and (select d.resultado from public.os_tarefas_dia d
                              where d.tarefa_id = t.id and d.estado = 'planejada' and d.termina and d.resultado is not null
                              order by d.dia desc, d.turno = 'tarde' desc limit 1) = 'sem_registro')),
    'risco_sem_quem_atende', v_risco);
end;
$function$;

comment on function public.agenda_tarefas_medidas(date, date, date) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.5, §16.11; R5.2-3): as medidas das etapas de p_de a p_ate (as linhas ligadas que terminam) — {planejadas, feitas_no_dia, pendentes, sem_registro, ppc_etapas (feitas ÷ (feitas + pendentes); o sem registro fica fora), alertas_2_dias, nao_cabe, sem_quem, respostas {com_lista, entendidas, nao_entendidas}, escopo_novo, concluidas_com_pendencia (OS concluídas na janela com etapa viva pendente dita), concluidas_sem_confirmacao (só com etapa viva sem registro), risco_sem_quem_atende (as linhas de etapa de risco cujo meio-dia não atende pela regra de hoje: tem de ser 0)}. O placar do 7g pode ler. Com login, só admin/financeiro (42501); sem login, só o service_role. STABLE; definer (a spec dizia invoker: _agenda_atende não tem grant); authenticated e service_role.';

-- ── A conversa: o rascunho etapa (§16.5.6) ────────────────────────────────────────────────────────────────────────────────

-- A etapa pelas palavras (R5.10-10: nunca pelo número — as listas que o dono vê numeram pelo dia, e a OS numera diferente): a única etapa
-- viva ou feita da OS cujo texto tem todas as palavras de 4 letras ou mais de p_etapa (no começo de uma palavra dele).
create or replace function public._agenda_tarefa_casar(p_os uuid, p_etapa text)
 returns uuid
 language sql
 stable
 set search_path to 'public'
as $function$
  with w as (select array(select x from unnest(regexp_split_to_array(public._agenda_normal(coalesce(p_etapa, '')), '\s+')) x
                           where char_length(x) >= 4 and x !~ '^[0-9]+$' and x not in ('etapa', 'servico', 'fazer')) as ws),
       c as (select t.id from public.os_tarefas t, w
              where t.service_order_id = p_os and t.estado in ('viva', 'feita') and cardinality(w.ws) > 0
                and not exists (select 1 from unnest(w.ws) x where not (public._agenda_normal(t.texto) ~ ('\m' || x))))
  select case when (select count(*) from c) = 1 then (select id from c) end;
$function$;

comment on function public._agenda_tarefa_casar(uuid, text) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.6; R5.10-10): a etapa da OS pelas palavras do dono — a única viva ou feita cujo texto (normalizado) tem todas as palavras de 4 letras ou mais de p_etapa no começo de uma palavra dele ("a substituição das baterias" → "Substituição baterias - chumbo para litio"); só números, nenhuma ou mais de uma = nulo (nunca pelo número: as listas do dia e a da OS numeram diferente). STABLE, sem grant.';

-- A releitura de uma linha etapa (§16.6.9). A linha da releitura já começa pelo rótulo da OS ("Lenine (OS-00074): "), então a frase não
-- repete o nome (o desvio 2 do P4).
create or replace function public._agenda_etapa_frase(p_d jsonb)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_d ->> 'forma'
    when 'estado' then format('"%s" %s', p_d ->> 'texto_etapa',
                              case p_d ->> 'estado' when 'feita' then 'já está feita' when 'falta' then 'ainda falta'
                                                    else 'não vai ser feita' end)
    when 'nova' then format('acrescentar "%s" (no fim, antes de testar e entregar)', p_d ->> 'texto')
    when 'dividir' then format('dividir "%s" em %s: %s', p_d ->> 'texto_etapa', jsonb_array_length(p_d -> 'partes'),
                               array_to_string(array(select x from jsonb_array_elements_text(p_d -> 'partes') with ordinality u(x, o)
                                                      order by o), '; '))
  end;
$function$;

comment on function public._agenda_etapa_frase(jsonb) is
  'Agenda de Produção (Fase 7c, P8; spec §16.6.9): a releitura de uma linha de rascunho etapa, dos dados — (a) estado: ""Instalação de porta fusíveis - distribuição de energia 12v" já está feita" · "… ainda falta" · "… não vai ser feita"; (b) nova: "acrescentar "Trocar a bomba d''água" (no fim, antes de testar e entregar)"; (c) dividir: "dividir "Instalação do novo sistema elétrico LiFePO4/Usina" em 3: Fixar o banco de baterias; Passar os cabos; Montar o quadro". A linha da releitura começa pelo rótulo da OS, e a frase não repete o nome. IMMUTABLE; só service_role (como _agenda_rascunho_frase, que a chama).';

-- A RPC da ferramenta servico_etapa (§16.5.6): o que o dono disse das etapas vira RASCUNHO (nada em os_tarefas).
create or replace function public.agenda_rascunho_etapa(p_autor uuid, p_canal text, p_os text, p_etapa text default null,
                                                        p_estado text default null, p_texto text default null,
                                                        p_partes text[] default null, p_trecho text default null,
                                                        p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  c        public.agenda_config := public._agenda_cfg();
  v_etapa  text := nullif(btrim(coalesce(p_etapa, '')), '');
  v_estado text := nullif(lower(btrim(coalesce(p_estado, ''))), '');
  v_texto  text := nullif(btrim(coalesce(p_texto, '')), '');
  v_partes text[] := array(select btrim(x) from unnest(coalesce(p_partes, '{}'::text[])) x where btrim(x) <> '');
  v_tr     text := public._agenda_normal(coalesce(p_trecho, ''));
  v_ro     jsonb;
  v_os     uuid;
  v_cli    text;
  t        public.os_tarefas%rowtype;
  v_lista  text;
  v_chave  text;
  v_dados  jsonb;
  v_item   text;
  v_base   text;
  v_p      text;
  v_w      text[];
  c_forma  constant text := 'Diga uma coisa por vez: uma etapa feita ou que falta, uma etapa nova ou dividir uma etapa.';
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_etapa: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  if v_estado is not null and v_estado not in ('feita', 'falta', 'nao_se_aplica') then
    raise exception 'agenda_rascunho_etapa: estado "%" não existe (feita, falta ou nao_se_aplica)', p_estado using errcode = '22023';
  end if;
  -- Exatamente uma das 3 formas, inteira: (a) etapa + estado; (b) texto; (c) etapa + partes.
  if (case when v_estado is not null then 1 else 0 end + case when v_texto is not null then 1 else 0 end
      + case when cardinality(v_partes) > 0 then 1 else 0 end) <> 1
     or (v_estado is not null and v_etapa is null)
     or (cardinality(v_partes) > 0 and v_etapa is null)
     or (v_texto is not null and v_etapa is not null) then
    raise exception '%', c_forma using errcode = '22023';
  end if;
  if cardinality(v_partes) > 0
     and (cardinality(v_partes) not between 2 and 6
          or exists (select 1 from unnest(v_partes) x where char_length(x) not between 3 and 60)
          or (select count(distinct public._agenda_normal(x)) from unnest(v_partes) x) <> cardinality(v_partes)) then
    raise exception 'agenda_rascunho_etapa: as partes são de 2 a 6, cada uma de 3 a 60 letras, todas diferentes' using errcode = '22023';
  end if;
  if c.modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora: não anotei nada.', 'desligada');
  end if;
  if c.modo_tarefas = 'desligado' then
    return public._agenda_recusa('As etapas dos serviços ainda estão desligadas: não anotei nada.', 'etapas_desligadas');
  end if;
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que mudou nas etapas.', 'sem_trecho');
  end if;
  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;
  v_cli := coalesce(nullif(v_ro ->> 'cliente_curto', ''), v_ro ->> 'numero');
  -- A OS ainda sem etapas gravadas (a rodada não passou por ela): sincroniza agora (é o dado do sistema, não a decisão do dono).
  if not exists (select 1 from public.os_tarefas x where x.service_order_id = v_os) then
    perform public._agenda_tarefas_sincronizar(v_os, p_hoje, clock_timestamp());
  end if;
  v_lista := public._agenda_lista(array(select x.texto from public.os_tarefas x where x.service_order_id = v_os and x.estado = 'viva'
                                         order by x.ordem, x.id), 4);

  if v_etapa is not null then
    -- só pelas palavras (R5.10-10): o número não vale
    if btrim(regexp_replace(public._agenda_normal(v_etapa), '\m(a|o|as|os|etapa|n|numero|no|na)\M', '', 'g')) ~ '^[0-9 ]+$' then
      return public._agenda_recusa(format('Me diga pelo nome: no %s faltam %s.', v_cli, coalesce(v_lista, 'nenhuma etapa')), 'numero');
    end if;
    select x.* into t from public.os_tarefas x where x.id = public._agenda_tarefa_casar(v_os, v_etapa);
    if t.id is null then
      return public._agenda_recusa(format('Não acho essa etapa no %s. As que faltam: %s.', v_cli, coalesce(v_lista, 'nenhuma')),
                                   'nao_achei');
    end if;
  end if;

  if v_estado is not null then
    -- (a) feita, falta ou não se aplica. A guarda: a palavra do estado e uma palavra da etapa no trecho.
    if not (v_tr ~ case v_estado when 'feita' then '\m(feit|pront|termin|instalad|passad|trocad|conclu)'
                                 when 'falta' then '\m(falt|ainda nao|nao termin)'
                                 else '\m(nao precisa|nao vai|cancel|tira)' end)
       or not exists (select 1 from unnest(regexp_split_to_array(public._agenda_normal(t.texto), '\s+')) w
                       where char_length(w) >= 4 and v_tr ~ ('\m' || left(w, 5))) then
      return public._agenda_recusa(format('Não achei no que você disse qual etapa do %s; me diga de novo.', v_cli), 'fora_do_trecho');
    end if;
    v_dados := public._agenda_os_do_rascunho(v_ro)
               || jsonb_build_object('forma', 'estado', 'cliente', v_cli, 'tarefa', t.id, 'texto_etapa', t.texto, 'estado', v_estado);
    v_chave := format('etapa:%s:%s', v_os, t.id);
  elsif v_texto is not null then
    -- (b) a etapa nova, com as palavras do dono (toda palavra de 4 letras ou mais do texto está no trecho)
    if char_length(v_texto) > 60 then
      return public._agenda_recusa('A etapa nova passa de 60 letras: diga mais curto.', 'texto_longo');
    end if;
    if exists (select 1 from unnest(regexp_split_to_array(public._agenda_normal(v_texto), '\s+')) w
                where char_length(w) >= 4 and not (' ' || v_tr || ' ') like ('% ' || w || ' %')) then
      return public._agenda_recusa(format('Para acrescentar, preciso das suas palavras: o que entra no %s?', v_cli), 'fora_do_trecho');
    end if;
    v_dados := public._agenda_os_do_rascunho(v_ro)
               || jsonb_build_object('forma', 'nova', 'cliente', v_cli, 'texto', upper(left(v_texto, 1)) || substr(v_texto, 2));
    v_chave := format('etapa:%s:nova:%s', v_os, md5(public._agenda_normal(v_texto)));
  else
    -- (c) dividir: a etapa viva e ainda não feita em parte; cada parte tem uma palavra da base (a linha, o roteiro, o material, o trecho)
    if t.estado <> 'viva' or exists (select 1 from public.os_tarefas_dia d where d.tarefa_id = t.id and d.resultado = 'feita') then
      return public._agenda_recusa('Essa etapa já começou a ser feita: não dá para dividir.', 'ja_feita');
    end if;
    v_base := public._agenda_normal(concat_ws(' ',
      (select s.name_snapshot from public.service_order_services s where s.id = t.service_order_service_id),
      (select string_agg(st.title, ' ') from public.service_order_steps st where st.id = any (t.passos)),
      (select string_agg(concat_ws(' ', pr.name, sp.notes), ' ') from public.service_order_parts sp
         left join public.products pr on pr.id = sp.product_id where sp.service_order_id = v_os),
      p_trecho));
    foreach v_p in array v_partes loop
      v_w := array(select w from unnest(regexp_split_to_array(public._agenda_normal(v_p), '\s+')) w
                    where char_length(w) >= 4 and w not in ('fazer', 'servico', 'etapa'));
      if not exists (select 1 from unnest(v_w) w where v_base ~ ('\m' || left(w, 5))) then
        return public._agenda_recusa(format('Para dividir, cada parte tem de vir do serviço, do roteiro, do material da OS ou do que você disse: "%s" não tem de onde vir.', v_p),
                                     'parte_sem_base');
      end if;
    end loop;
    v_dados := public._agenda_os_do_rascunho(v_ro)
               || jsonb_build_object('forma', 'dividir', 'cliente', v_cli, 'tarefa', t.id, 'texto_etapa', t.texto,
                                     'partes', to_jsonb(v_partes));
    v_chave := format('etapa:%s:dividir:%s', v_os, t.id);
  end if;

  v_item := public._agenda_rascunho_salvar(v_autor, p_canal, 'etapa', v_chave, v_os, v_dados, p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_item, 'itens', jsonb_build_array(v_item),
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_etapa(uuid, text, text, text, text, text, text[], text, date) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.6, §16.7; R5.10-10, -11): a ferramenta servico_etapa — o que o dono disse das etapas de uma OS vira RASCUNHO (nada em os_tarefas). Uma de 3 formas por chamada (senão 22023 "Diga uma coisa por vez: uma etapa feita ou que falta, uma etapa nova ou dividir uma etapa."): (a) p_etapa + p_estado (feita, falta, nao_se_aplica), a etapa pelas palavras (_agenda_tarefa_casar; só o número = "Me diga pelo nome: no Lenine faltam …."; não achou = "Não acho essa etapa no Lenine. As que faltam: …."), a guarda: a palavra do estado e uma palavra da etapa no trecho, chave etapa:<os>:<tarefa>; (b) p_texto (até 60 letras; toda palavra de 4 letras ou mais dele no trecho), chave etapa:<os>:nova:<md5>; (c) p_etapa + p_partes (2 a 6, de 3 a 60 letras, distintas; a etapa viva sem linha feita; cada parte com uma palavra da linha, do roteiro, do material da OS ou do trecho), chave etapa:<os>:dividir:<tarefa>. A OS por agenda_resolver_os (ambígua ou não achada = a pergunta); sem etapas gravadas, sincroniza antes. Com modo_leitura ou modo_tarefas desligado não anota. Devolve {ok, item, itens, releitura} ou {ok: false, pergunta}. Quem chama: só o administrador (_autor_da_agenda); authenticated (o painel) e service_role (o WhatsApp) — a spec dizia só service_role (o desvio 1 do P4).';

-- O *grava* de uma linha etapa (§16.5.6, §16.6.9; R5.2-3): feita, falta (a pendente dita), não se aplica, a nova e a divisão.
create or replace function public._agenda_aplicar_etapa(p_autor uuid, p_dados jsonb, p_trecho text, p_hoje date, p_agora timestamptz)
 returns text
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_casa  constant numeric := 0.001;   -- estrutural: a menor casa de os_tarefas.ordem (numeric(8,3))
  cf      public.agenda_config := public._agenda_cfg();
  v_os    uuid := (p_dados ->> 'os')::uuid;
  v_cli   text := coalesce(p_dados ->> 'cliente', p_dados ->> 'curto');
  t       public.os_tarefas%rowtype;
  v_lin   uuid[];
  v_x     numeric;
  v_ant   numeric;
  v_ord   numeric;
  v_fase  smallint;
  v_ex    int;
  v_n     int;
  v_step  numeric;
  v_k     int;
  v_p     text;
  v_fim   boolean;
begin
  if p_dados ->> 'forma' in ('estado', 'dividir') then
    select * into t from public.os_tarefas x where x.id = (p_dados ->> 'tarefa')::uuid for update;
    if t.id is null or t.estado not in ('viva', 'feita') then
      raise exception 'a etapa "%" do % mudou', p_dados ->> 'texto_etapa', v_cli using errcode = 'P0097';
    end if;
  end if;

  if p_dados ->> 'forma' = 'estado' then
    if p_dados ->> 'estado' = 'feita' then
      if t.estado = 'viva' then
        update public.os_tarefas
           set estado = 'feita', feita_em = p_agora, feita_via = 'dono', pendente_vezes = 0, pendente_desde = null, pendente_ultimo = null,
               mudou_em = p_agora
         where id = t.id;
      end if;
      v_lin := array(select d.id from public.os_tarefas_dia d
                      where d.tarefa_id = t.id and d.estado = 'planejada' and d.termina and d.resultado is null and d.dia <= p_hoje);
      perform public._agenda_tarefas_registrar(v_lin, 'feita', 'dono', p_trecho, null, p_agora);
      return format('%s: "%s" feita.', v_cli, t.texto);
    elsif p_dados ->> 'estado' = 'falta' then
      if t.estado = 'feita' then
        update public.os_tarefas set estado = 'viva', feita_em = null, feita_via = null, mudou_em = p_agora where id = t.id;
      end if;
      -- a pendente dita pelo dono (R5.2-3, R5.10-11): grava pendente via dono nas linhas congeladas dela que já passaram (por cima)
      v_lin := array(select d.id from public.os_tarefas_dia d
                      where d.tarefa_id = t.id and d.estado = 'planejada' and d.termina and d.dia <= p_hoje);
      perform public._agenda_tarefas_registrar(v_lin, 'pendente', 'dono', p_trecho, null, p_agora);
      return format('%s: "%s" volta a faltar.', v_cli, t.texto);
    else
      if t.estado = 'feita' then
        update public.os_tarefas set estado = 'viva', feita_em = null, feita_via = null, mudou_em = p_agora where id = t.id;
      end if;
      update public.os_tarefas set estado = 'nao_se_aplica', mudou_em = p_agora where id = t.id;
      return format('%s: "%s" não vai ser feita.', v_cli, t.texto);
    end if;
  end if;

  if p_dados ->> 'forma' = 'nova' then
    if not exists (select 1 from public.os_tarefas x where x.service_order_id = v_os) then
      perform public._agenda_tarefas_sincronizar(v_os, p_hoje, p_agora);
    end if;
    v_fase := public._agenda_tarefa_fase(p_dados ->> 'texto', cf.tarefas_fases);
    if v_fase >= 5 then
      select min(x.ordem) into v_x from public.os_tarefas x where x.service_order_id = v_os and x.estado = 'viva' and x.chave = 'entrega';
    else
      select min(x.ordem) into v_x from public.os_tarefas x where x.service_order_id = v_os and x.estado = 'viva' and x.fase >= 5;
    end if;
    v_fim := v_x is not null;
    if v_x is null then
      select coalesce(max(x.ordem), 0) + 1 into v_ord from public.os_tarefas x where x.service_order_id = v_os;
    else
      select coalesce(max(x.ordem), v_x - 1) into v_ant from public.os_tarefas x where x.service_order_id = v_os and x.ordem < v_x;
      v_ord := round((v_ant + v_x) / 2, 3);
      if v_ord <= v_ant or v_ord >= v_x then
        v_ord := v_x - c_casa;
      end if;
    end if;
    -- o que a OS pede sem linha, em todos os dias, vai a toda etapa (também a do dono)
    begin
      select coalesce(bit_or(case i ->> 'exigencia' when 'energizado' then 1 when 'comissionamento' then 2 when 'altura' then 4 else 8 end), 0)
        into v_ex
        from jsonb_array_elements(coalesce(public.os_exigencias(v_os, p_hoje) -> 'itens', '[]'::jsonb)) i
       where i ->> 'linha_id' is null and i ->> 'meios' = 'todos';
    exception when sqlstate '42501' then
      v_ex := 0;
    end;
    insert into public.os_tarefas (service_order_id, chave, origem, texto, fase, ordem, horas, exige, estado, nova_no_escopo, trecho,
                                   criada_em, criada_por, mudou_em)
    values (v_os, 'dono:' || gen_random_uuid(), 'dono', left(p_dados ->> 'texto', 80), v_fase, v_ord, cf.tarefas_horas_min, v_ex,
            'viva', true, left(coalesce(nullif(btrim(p_trecho), ''), p_dados ->> 'texto'), 500), p_agora,
            (select u.id from public.app_users u where u.id = p_autor), p_agora);
    return format('%s: entrou "%s", %s', v_cli, p_dados ->> 'texto', case when v_fim then 'antes de testar e entregar.' else 'no fim.' end);
  end if;

  if p_dados ->> 'forma' = 'dividir' then
    if t.estado <> 'viva' or exists (select 1 from public.os_tarefas_dia d where d.tarefa_id = t.id and d.resultado = 'feita') then
      raise exception 'a etapa "%" do % já começou a ser feita', t.texto, v_cli using errcode = 'P0097';
    end if;
    v_n := jsonb_array_length(p_dados -> 'partes');
    select min(x.ordem) into v_x from public.os_tarefas x where x.service_order_id = v_os and x.ordem > t.ordem;
    -- (§16.5.6) as partes em ordem + k/10, ou mais junto quando a etapa seguinte está mais perto
    v_step := least(coalesce((v_x - t.ordem) * 10 / (v_n + 1), 1), 1) / 10;
    update public.os_tarefas set estado = 'substituida', mudou_em = p_agora where id = t.id;
    v_k := 0;
    for v_p in select x from jsonb_array_elements_text(p_dados -> 'partes') with ordinality u(x, o) order by o loop
      v_k := v_k + 1;
      insert into public.os_tarefas (service_order_id, chave, origem, service_order_service_id, pai_id, texto, fase, ordem, horas, exige,
                                     passos, estado, nova_no_escopo, trecho, criada_em, criada_por, mudou_em)
      values (v_os, left(t.chave, 110) || ':' || v_k, 'ia', t.service_order_service_id, t.id,
              upper(left(v_p, 1)) || substr(v_p, 2), t.fase, round(t.ordem + v_k * v_step, 3), round(t.horas / v_n, 2),
              t.exige, '{}', 'viva', t.nova_no_escopo, left(coalesce(nullif(btrim(p_trecho), ''), v_p), 500), p_agora,
              (select u.id from public.app_users u where u.id = p_autor), p_agora);
    end loop;
    return format('%s: "%s" virou %s etapas.', v_cli, t.texto, v_n);
  end if;
  raise exception '_agenda_aplicar_etapa: forma "%" não existe', p_dados ->> 'forma' using errcode = '22023';
end;
$function$;

comment on function public._agenda_aplicar_etapa(uuid, jsonb, text, date, timestamptz) is
  'Agenda de Produção (Fase 7c, P8; spec §16.5.6, §16.6.9; R5.2-3, R5.10-11): o *grava* de uma linha etapa — (a) feita: a etapa feita via dono e as linhas congeladas dela que já passaram, sem resultado, feita via dono (por _agenda_tarefas_registrar) — "Lenine: "…" feita."; falta: de feita volta a viva e grava pendente via dono nas linhas congeladas dela que já passaram, por cima (a pendente dita: segura a conclusão e conta o dia) — "… volta a faltar."; não se aplica — "… não vai ser feita."; (b) nova: viva, origem dono, chave dono:<uuid>, nova_no_escopo, horas = tarefas_horas_min, a fase pela régua, no fim antes de testar e entregar, a máscara do que a OS pede sem linha em todos os dias, o trecho e quem gravou — "Flávio: entrou "Trocar a bomba d''água", antes de testar e entregar."; (c) dividir: a etapa substituida e as partes vivas (origem ia, pai_id, chave <chave>:<k>, logo depois dela na ordem, o peso ÷ n, a máscara e a fase dela, o trecho do dono) — "Vanderlei: "…" virou 3 etapas.". A etapa que mudou desde a releitura = P0097. Só pelo *grava* (agenda_rascunho_gravar). Definer, sem grant.';

-- ── 6. As 9 recriadas (cada uma da definição MAIS NOVA; só inserções: os blocos "-- FASE 7c: (7c P8 …" e, na linha (n), as marcas de
-- dentro "-- (7c P8 …") ─────────────────────────────────────────────────────────────────────────────────────────────────────────────

-- _agenda_modo_da_pergunta (de 20261102100000_agenda_fase7c_base.sql)
create or replace function public._agenda_modo_da_pergunta(p_tipo text, p_chave text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_tipo in ('nao_cabe', 'segundo_atraso', 'atraso_longo', 'remarcar_confirmado', 'fixada_pelo_dono') then c.modo_proposta
    when p_tipo = 'chegou' and coalesce(p_chave, '') like 'chegou:fornecedor:%' then c.modo_material
    -- CORREÇÃO 29/10 (revisão): a equipe sem dias é da vigia.
    when p_tipo = 'equipe_sem_dias' then c.modo_vigia
    -- CORREÇÃO 29/10 (revisão): fim
    when p_tipo in ('conferencia', 'chegou', 'parada', 'estouro', 'duracao', 'material_conferir', 'padrao_do_dono', 'entrega')
      then c.modo_vigia
    when p_tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
      then c.modo_material
    when p_tipo in ('diaria', 'diaria_ligar') then c.modo_diaria
    when p_tipo in ('equipe_resposta', 'concluir') then c.modo_equipe
    when p_tipo in ('cliente_aprovar', 'cliente_aviso', 'cliente_resposta') then c.modo_cliente
    when p_tipo = 'aprendizado' then c.modo_aprendizado
    -- FASE 7: (7a P11) a pergunta da ficha da equipe de um dia pela estimativa (ficha_estimativa) é das mensagens à equipe
    -- (modo_equipe), não do gestor que marca: a proteção vale enquanto houver dia marcado pela estimativa na janela, também com
    -- *gestor, só propor* (sem isso a pergunta nasceria em teste e a ficha ficaria segurada sem o dono poder soltá-la). Vem antes
    -- da linha do 7a P1, que ainda a cita.
    when p_tipo = 'ficha_estimativa' then c.modo_equipe
    -- FASE 7: fim
    -- FASE 7b: (7b P1) a pergunta dos dias da semana ao dono (dias_semana) é do modo_dias; a chamada da equipe (equipe_cadastro)
    -- passa a ser do modo_cadastro quando ele sai de desligado (o 7b P3 faz o passo equipe do gestor ceder: uma pergunta só);
    -- desligado, continua a do gestor que marca (a linha do 7a P1, abaixo, que ainda a cita). Vem antes dela.
    when p_tipo = 'dias_semana' then c.modo_dias
    when p_tipo = 'equipe_cadastro' and c.modo_cadastro <> 'desligado' then c.modo_cadastro
    -- FASE 7b: fim
    -- FASE 7c: (7c P1) a pergunta de quem faz o quê (habilidade): a da equipe (habilidade:equipe:…, a proposta pelo histórico) é do
    -- modo_habilidade_propor; a de uma OS (habilidade:os:<os>, "ninguém com isso fica livre") é do modo_habilidade.
    when p_tipo = 'habilidade' and coalesce(p_chave, '') like 'habilidade:os:%' then c.modo_habilidade
    when p_tipo = 'habilidade' then c.modo_habilidade_propor
    -- FASE 7c: fim
    -- FASE 7c: (7c P8, R5.4) as perguntas das etapas (tarefa: tarefa:prazo:<os>, "o que falta não cabe até o prazo", e tarefa:quem:<os>,
    -- "a etapa de risco sem quem faça") são do modo_tarefas.
    when p_tipo = 'tarefa' then c.modo_tarefas
    -- FASE 7c: fim
    -- FASE 7: os tipos do gestor da agenda (7a P1). O dia avisado e o prometido são críticas do plano, como o remarcar
    -- confirmado; a revisão diária faz reavaliar e reestimar; a cobrança do "compre até", a dela; o resto é do gestor que marca.
    when p_tipo in ('dia_avisado', 'dia_prometido') then c.modo_proposta
    when p_tipo in ('reavaliar', 'reestimar') then public._agenda_gestor_modo('revisao')
    when p_tipo = 'compre_ate' then public._agenda_gestor_modo('compre_ate')
    when p_tipo in ('situacao', 'estimativa', 'equipe_cadastro', 'ficha_estimativa', 'bem_livre', 'sinal', 'onda', 'sabado')
      then public._agenda_gestor_modo('marcar')
    -- FASE 7: fim
  end
    from public.agenda_config c
   where c.id;
$function$;

comment on function public._agenda_modo_da_pergunta(text, text) is
  'Agenda de Produção (correção de 29/10, P3): o modo de agenda_config de quem grava cada tipo de pergunta — críticas do plano: modo_proposta; conferencia, chegou, parada, estouro, duracao, material_conferir, padrao_do_dono, entrega: modo_vigia; chegou:fornecedor:…, nfe_vincular, pix_material, previsao_fornecedor, fornecedor_cadastro, fornecedores_prazo: modo_material; diaria, diaria_ligar: modo_diaria; equipe_resposta, concluir: modo_equipe; cliente_*: modo_cliente; aprendizado: modo_aprendizado; outro tipo: null. A limpeza da vigia fecha a pergunta aberta em sombra quando este modo está ligado. STABLE, invoker, só o service_role. CORREÇÃO 29/10 (revisão): o tipo novo equipe_sem_dias é da vigia (modo_vigia). Fase 7a (P1): dia_avisado e dia_prometido = modo_proposta (críticas do plano); reavaliar e reestimar = o modo da revisão do gestor; compre_ate = o da cobrança; situacao, estimativa, equipe_cadastro, ficha_estimativa, bem_livre, sinal, onda e sabado = o do gestor que marca (_agenda_gestor_modo). Fase 7a (P11): ficha_estimativa = modo_equipe (a pergunta é das mensagens à equipe: a proteção da ficha vale com *gestor, só propor*); o bloco vem antes da linha do P1, que ainda a cita. Fase 7b (P1): dias_semana = modo_dias (a pergunta dos dias da semana ao dono); equipe_cadastro = modo_cadastro fora de desligado (a chamada da equipe passa a ser da 7b), senão o do gestor que marca, como antes. Fase 7c (P1): habilidade = modo_habilidade_propor (a pergunta de quem faz o quê da equipe, habilidade:equipe:…) ou modo_habilidade (a de uma OS, habilidade:os:<os>). FASE 7c (P8, R5.4): o tipo tarefa (tarefa:prazo:<os> e tarefa:quem:<os>, as exceções das etapas) é do modo_tarefas.';

-- _agenda_rascunho_frase (de 20261102100300_agenda_fase7c_conversa.sql)
create or replace function public._agenda_rascunho_frase(p_tipo text, p_d jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_partes text[] := '{}';
  v_t      text;
  v_forn   text := nullif(p_d ->> 'fornecedor_txt', '');
  v_hoje   date := (p_d ->> 'hoje')::date;
  v_quando text;
  -- FASE 4: (P3) de onde veio o aviso ("nota 51038 da Kamell", "Pix de R$ 480,00 à Premel, seg 26/10").
  v_aviso  text;
  -- FASE 4: fim
  -- FASE 7b: (7b P2) a semana dita e as datas
  v_7b_dias smallint[];
  v_7b_fora smallint[];
  v_7b_n    int;
  -- FASE 7b: fim
begin
  if p_tipo = 'planejar' then
    if nullif(p_d ->> 'escopo_decidido', '') is not null then
      v_partes := v_partes || (p_d ->> 'escopo_decidido');
    end if;
    v_t := null;
    if p_d ->> 'dias' is not null then
      v_t := public._agenda_dias((p_d ->> 'dias')::numeric)
             || case when p_d ->> 'estimativa_fonte' = 'aceita' then ' (a minha estimativa, que você aceitou)' else '' end;
    end if;
    if jsonb_array_length(coalesce(p_d -> 'equipe', '[]'::jsonb)) > 0 then
      v_t := concat_ws(' ', v_t, 'com ' || public._agenda_lista(array(
               select case when (e ->> 'eh_dono')::boolean then 'você' else e ->> 'nome' end
                      || case e ->> 'turnos' when 'manha' then ' (de manhã)' when 'tarde' then ' (à tarde)' else '' end
                 from jsonb_array_elements(p_d -> 'equipe') with ordinality t(e, o) order by o), null));
    elsif p_d ? 'equipe' and p_d ->> 'dias' is null then
      v_t := 'sem ninguém marcado para ir';
    end if;
    if v_t is not null then
      v_partes := v_partes || v_t;
    end if;
    if p_d ->> 'dono' is not null then
      v_partes := v_partes || case p_d ->> 'dono' when 'abre_e_fecha' then 'você abre e fecha'
                                                 when 'sempre' then 'você fica o tempo todo' else 'você não vai' end;
    end if;
    if p_d ->> 'precisa_ate' is not null then
      v_partes := v_partes || ('o cliente precisa até ' || public._dia_curto((p_d ->> 'precisa_ate')::date));
    elsif p_d ? 'precisa_ate' then
      v_partes := v_partes || 'o cliente não tem mais prazo'::text;
    end if;
    if p_d ? 'bem' then
      v_partes := v_partes || case p_d #>> '{bem,modo}'
        when 'livre' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' já está livre'
        when 'fora' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica fora '
                         || public._agenda_quando_texto((p_d #>> '{bem,de}')::date, (p_d #>> '{bem,ate}')::date)
        else coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica livre ' || public._dia_curto((p_d #>> '{bem,livre_em}')::date) end;
    end if;
    if p_d ->> 'nao_antes_de' is not null then
      v_partes := v_partes || ('não antes de ' || public._dia_curto((p_d ->> 'nao_antes_de')::date)
                               || case when coalesce(p_d ->> 'nao_antes_motivo', 'você disse') = 'você disse' then ''
                                       else ' (' || (p_d ->> 'nao_antes_motivo') || ')' end);
    elsif p_d ? 'nao_antes_de' then
      v_partes := v_partes || 'pode começar sem esperar data'::text;
    end if;
    if nullif(p_d ->> 'escopo_em_aberto', '') is not null then
      v_partes := v_partes || ('falta decidir: ' || (p_d ->> 'escopo_em_aberto'));
    elsif p_d ? 'escopo_em_aberto' and nullif(p_d ->> 'escopo_decidido', '') is null then
      v_partes := v_partes || 'nada mais a decidir no escopo'::text;
    end if;
    if p_d ->> 'congelada_ate' is not null then
      v_partes := v_partes || ('em espera até ' || public._dia_curto((p_d ->> 'congelada_ate')::date)
                               || case when p_d ->> 'revisar_em' is distinct from p_d ->> 'congelada_ate'
                                       then ' (rever ' || public._dia_curto((p_d ->> 'revisar_em')::date) || ')' else '' end);
    elsif p_d ? 'congelada_ate' then
      v_partes := v_partes || 'sai da espera'::text;
    end if;
    if p_d ->> 'prioridade' is not null then
      v_partes := v_partes || case when (p_d ->> 'prioridade')::int = 1 then 'passa na frente (prioridade 1)'
                                   else 'prioridade ' || (p_d ->> 'prioridade') end;
    end if;
    if p_d ->> 'sem_material' is not null then
      v_partes := v_partes || case when (p_d ->> 'sem_material')::boolean then 'não tem peça a comprar'
                                   else 'tem peça a conferir' end;
    end if;
    -- FASE 2: quanto dá para adiantar no pátio sem o bem (bancada: barramento, chicote).
    if p_d ? 'adiantavel_patio' then
      v_partes := v_partes || case when p_d ->> 'adiantavel_patio' is null then 'nada a adiantar no pátio'
                                   else 'dá para adiantar ' || public._agenda_dias((p_d ->> 'adiantavel_patio')::numeric) || ' no pátio' end;
    end if;
    -- FASE 5: o que o dono disse ao cliente ("você disse ao Flávio: ter 03/11 (data firme)") e como o serviço é dito a ele
    if jsonb_typeof(p_d -> 'prometido') = 'object' then
      v_partes := v_partes || format('você disse ao %s: %s (%s)', coalesce(nullif(p_d ->> 'curto', ''), 'cliente'),
        case when p_d #>> '{prometido,de}' = p_d #>> '{prometido,ate}' then public._dia_curto((p_d #>> '{prometido,ate}')::date)
             else format('de %s a %s', public._dia_curto((p_d #>> '{prometido,de}')::date),
                         public._dia_curto((p_d #>> '{prometido,ate}')::date)) end,
        case when p_d #>> '{prometido,tipo}' = 'firme' then 'data firme' else 'uma faixa' end);
    end if;
    if nullif(p_d ->> 'servico_cliente', '') is not null then
      v_partes := v_partes || format('o serviço, para o cliente: %s', p_d ->> 'servico_cliente');
    end if;
    -- FASE 5: fim
    -- FASE 7b: (7b P2, §6.6) a dupla dita ("vai com 1 pessoa só", "vai em dupla o tempo todo", "vai em dupla nos 2 primeiros
    -- meios-dias") e, com menos técnicos do que ela pede, o aviso de que a OS espera
    if p_d ->> 'dupla' is not null then
      v_7b_n := (p_d ->> 'dupla_meios')::int;
      v_partes := v_partes || case p_d ->> 'dupla'
        when 'nao' then 'vai com 1 pessoa só'
        when 'todos' then 'vai em dupla o tempo todo'
        when 'inicio' then case when v_7b_n = 1 then 'vai em dupla no primeiro meio-dia'
                                else format('vai em dupla nos %s primeiros meios-dias', v_7b_n) end
        else case when v_7b_n = 1 then 'vai em dupla no último meio-dia'
                  else format('vai em dupla nos %s últimos meios-dias', v_7b_n) end end;
    end if;
    if nullif(p_d ->> 'dupla_aviso', '') is not null then
      return array_to_string(v_partes, '; ') || '. ' || (p_d ->> 'dupla_aviso');
    end if;
    -- FASE 7b: fim
    return array_to_string(v_partes, '; ');
  end if;

  if p_tipo = 'material' then
    v_t := case p_d ->> 'acao'
      when 'na_mao' then
        case when p_d ->> 'quantidade_na_mao' is not null
             then format('%s de %s na mão', public._os_material_qtd((p_d ->> 'quantidade_na_mao')::numeric),
                         public._os_material_qtd((p_d ->> 'quantidade_necessaria')::numeric))
             when (p_d ->> 'chegou_em')::date = v_hoje then 'na mão (desde hoje)'
             else 'na mão desde ' || public._dia_curto((p_d ->> 'chegou_em')::date) end
      when 'comprado' then
        'comprado' || case when (p_d ->> 'comprado_em')::date = v_hoje then ' hoje'
                           else ' em ' || public._dia_curto((p_d ->> 'comprado_em')::date) end
        || case when p_d ->> 'previsao_ate' is not null
                then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' else '' end
      when 'a_caminho' then
        case when p_d ->> 'previsao_ate' is null then 'a caminho, sem previsão'
             when p_d ->> 'previsao_de' is not null then
               format('chega entre %s e %s (você disse)', public._dia_curto((p_d ->> 'previsao_de')::date),
                      public._dia_curto((p_d ->> 'previsao_ate')::date))
             else 'chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' end
      when 'falta' then
        case when coalesce((p_d ->> 'vou_comprar')::boolean, false) then
               case when p_d ->> 'compra_prevista_em' is null then 'você vai comprar'
                    else 'você compra ' || public._dia_curto((p_d ->> 'compra_prevista_em')::date) end
             else 'falta comprar' end
      when 'sem_previsao' then 'comprado, sem previsão de chegada'
      when 'dispensado' then 'não precisa mais (sai da lista)'
      else null end;
    -- FASE 4: (P3) o aviso (a nota, o Pix ou a mensagem que a agenda perguntou) diz de onde veio; o fornecedor já está nele.
    if jsonb_typeof(p_d -> 'aviso') = 'object' then
      v_aviso := p_d -> 'aviso' ->> 'curto';
      v_t := case
        when coalesce((p_d ->> 'nota_chegou')::boolean, false) then
          format('na mão desde %s (a %s entrou no estoque)', public._dia_curto((p_d ->> 'chegou_em')::date), v_aviso)
        when p_d ->> 'acao' = 'na_mao' and p_d ->> 'quantidade_na_mao' is null then
          format('na mão desde %s (%s)', case when (p_d ->> 'chegou_em')::date = v_hoje then 'hoje'
                                              else public._dia_curto((p_d ->> 'chegou_em')::date) end, v_aviso)
        when p_d ->> 'acao' = 'a_caminho' and p_d -> 'aviso' ->> 'tipo' = 'nfe' then
          'a caminho pela ' || v_aviso
          || case when p_d ->> 'previsao_ate' is null then ', sem previsão de chegada'
                  when p_d ->> 'previsao_fonte' = 'dono' then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)'
                  else ', chega por volta de ' || public._dia_curto((p_d ->> 'previsao_ate')::date) end
        when p_d ->> 'acao' = 'a_caminho' and p_d ->> 'previsao_ate' is not null and p_d ->> 'previsao_fonte' = 'fornecedor' then
          format('a caminho, chega por volta de %s (%s)', public._dia_curto((p_d ->> 'previsao_ate')::date), v_aviso)
        when p_d ->> 'acao' = 'comprado' and p_d -> 'aviso' ->> 'tipo' = 'pix' and p_d ->> 'previsao_ate' is null
             and v_aviso like 'Pix %' then
          'comprado pelo ' || v_aviso
        else coalesce(v_t || ' (' || v_aviso || ')', v_t) end;
      if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
        v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
      end if;
      return v_t;
    end if;
    -- FASE 4: fim
    if v_t is not null and v_forn is not null and p_d ->> 'acao' <> 'dispensado' then
      v_t := v_t || ', fornecedor ' || v_forn;
    end if;
    if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
      v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
    end if;
    return v_t;
  end if;

  if p_tipo = 'disponibilidade' then
    -- FASE 7b: (7b P2, §6.6, R4.2(c)) quem não está na equipe (a pessoa do cadastro): a frase de sempre e o aviso de que, com
    -- *grava*, ela entra
    if coalesce((p_d ->> 'fora_da_equipe')::boolean, false) then
      return public._agenda_rascunho_frase(p_tipo, p_d - 'fora_da_equipe')
             || format('. %s ainda não está na equipe da agenda: com *grava*, ele entra %s', p_d ->> 'nome',
                       case when coalesce((p_d ->> 'padrao')::boolean, false) then 'com esses dias, toda semana'
                            when p_d ? 'semana' or p_d ? 'datas' or p_d ->> 'de' is distinct from p_d ->> 'ate' then 'só nesses dias'
                            else 'só nesse dia' end);
    end if;
    -- a semana dita ("vem seg, ter e qui (e não vem qua e sex)"; o dono: "fica em campo seg e qua; nos outros dias, só abre e
    -- fecha"); o rótulo leva a semana ("Roberto, semana de 16/11")
    if p_d ? 'semana' then
      v_7b_dias := array(select jsonb_array_elements_text(coalesce(p_d -> 'dias_semana', '[]'::jsonb))::smallint);
      v_7b_fora := array(select x::smallint from generate_series(1, 5) x where not (x::smallint = any (v_7b_dias)) order by 1);
      if cardinality(v_7b_dias) = 0 and not coalesce((p_d ->> 'sabado')::boolean, false) then
        return case when (p_d ->> 'eh_dono')::boolean then 'só abre e fecha' else 'não vem' end;
      end if;
      if (p_d ->> 'eh_dono')::boolean then
        return 'fica em campo ' || public._agenda_dias_curtos(v_7b_dias, (p_d ->> 'sabado')::boolean)
               || case when cardinality(v_7b_fora) > 0 then '; nos outros dias, só abre e fecha' else '' end;
      end if;
      return 'vem ' || public._agenda_dias_curtos(v_7b_dias, (p_d ->> 'sabado')::boolean)
             || case when cardinality(v_7b_fora) > 0 then ' (e não vem ' || public._agenda_dias_curtos(v_7b_fora) || ')' else '' end;
    end if;
    -- as datas de quem vem sob demanda ("vem qua 11/11 e qui 12/11 (só nesses dias)")
    if p_d ? 'datas' then
      return case when (p_d ->> 'eh_dono')::boolean then 'em campo ' else 'vem ' end
             || public._agenda_lista(array(select public._dia_curto(x::date)
                                                  || case when extract(isodow from x::date)::int = 6 then ' de manhã' else '' end
                                             from jsonb_array_elements_text(p_d -> 'datas') with ordinality t(x, o) order by o), null)
             || ' (só nesses dias)';
    end if;
    -- FASE 7b: fim
    v_quando := case when (p_d ->> 'padrao')::boolean
                     then public._agenda_dias_semana_texto(array(select jsonb_array_elements_text(p_d -> 'dias_semana')::smallint))
                     else public._agenda_quando_texto((p_d ->> 'de')::date, (p_d ->> 'ate')::date) end;
    return case p_d ->> 'dito'
      when 'vem' then case when (p_d ->> 'eh_dono')::boolean then 'em campo ' else 'vem ' end || v_quando
      when 'nao_vem' then case when (p_d ->> 'eh_dono')::boolean then 'fora de campo ' else 'não vem ' end || v_quando
      when 'so_manha' then v_quando || ' à tarde, não'
      else v_quando || ' de manhã, não' end
      || case when coalesce((p_d ->> 'sabado_por_data')::boolean, false) then ' (sábado eu só conto por data)' else '' end;
  end if;

  -- FASE 2: os pedidos da conversa (marcar, aplicar/decidir, desfazer, andamento) chegam com a frase pronta do banco.
  if p_tipo in ('marcar', 'aplicar', 'desfazer', 'andamento') then
    return p_d ->> 'frase_pronta';
  end if;

  -- FASE 4: o prazo do fornecedor chega com a frase pronta do banco (agenda_rascunho_fornecedor).
  if p_tipo = 'fornecedor' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  -- FASE 4: (P3) "não é material de serviço" (a nota, o Pix ou a mensagem) chega com a frase pronta (agenda_rascunho_material).
  if p_tipo = 'aviso' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  -- FASE 7c: (7c P4, §5.4, §6.3) quem faz o quê, o que a OS pede e o responsável (agenda_rascunho_habilidade): a releitura sai dos
  -- dados (_agenda_habilidade_frase: "Roberto instala sozinho", "pede quem sobe no teto em todos os dias", "o responsável é Roberto
  -- (fica em todos os dias)", "fica como eu marquei (…)")
  if p_tipo = 'habilidade' then
    return public._agenda_habilidade_frase(p_d);
  end if;
  -- FASE 7c: fim
  -- FASE 7c: (7c P8, §16.5.6, §16.6.9) as etapas de um serviço (agenda_rascunho_etapa): a releitura sai dos dados (_agenda_etapa_frase:
  -- ""…" já está feita", "acrescentar "…" (no fim, antes de testar e entregar)", "dividir "…" em 3: …")
  if p_tipo = 'etapa' then
    return public._agenda_etapa_frase(p_d);
  end if;
  -- FASE 7c: fim
  raise exception '_agenda_rascunho_frase: tipo "%" não existe', p_tipo using errcode = '22023';
end;
$function$;

comment on function public._agenda_rascunho_frase(text, jsonb) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): a frase de uma linha do rascunho, montada dos dados já resolvidos — planejar ("2 dias com Roberto e João (à tarde); você abre e fecha; dá para adiantar 1 dia no pátio"), material ("chega ter 03/11 (você disse)", "você compra ter 27/10, fornecedor Premel") e disponibilidade ("em campo de seg a sex", "toda sexta à tarde, não"); os pedidos da Fase 2 (marcar, aplicar, desfazer, andamento), o prazo do fornecedor (Fase 4) e o "não é de serviço" (tipo aviso, Fase 4, P3) trazem a frase pronta (dados.frase_pronta); o material com o aviso diz de onde veio ("a caminho pela nota 51038 da Kamell, chega por volta de sex 30/10", "na mão desde hoje (Pix de R$ 480,00 à Premel, seg 26/10)", "na mão desde qua 28/10 (a nota 51038 da Kamell entrou no estoque)"). Fase 5 (P5): o planejar diz o que o dono disse ao cliente ("você disse ao Flávio: ter 03/11 (data firme)"; faixa: "de qua 04/11 a dom 08/11 (uma faixa)") e como o serviço é dito a ele ("o serviço, para o cliente: a instalação do compressor"). Fase 7b (P2, §6.6): o planejar com a dupla dita ("vai com 1 pessoa só", "vai em dupla o tempo todo", "vai em dupla nos 2 primeiros meios-dias", "… nos 2 últimos meios-dias"; 1 = "no primeiro meio-dia") e, com menos técnicos do que ela pede, o aviso "Hoje só Alex está na equipe: até você chamar alguém e me dizer os dias, eu não marco Lenine"; a disponibilidade com a semana ("vem seg, ter e qui (e não vem qua e sex)"; o dono: "fica em campo seg e qua; nos outros dias, só abre e fecha"; "não vem"; "só abre e fecha") e com as datas ("vem qua 11/11 e qui 12/11 (só nesses dias)"; o sábado "de manhã"); quem não está na equipe ganha "Mateus ainda não está na equipe da agenda: com *grava*, ele entra só nesses dias". FASE 7c (P4, §5.4, §6.3): o tipo habilidade sai de _agenda_habilidade_frase — "Roberto instala sozinho", "pede quem sobe no teto em todos os dias", "o responsável é Roberto (fica em todos os dias)", "fica sem responsável fixo", "fica como eu marquei (Roberto instala sozinho; João é ajudante)". Os outros tipos, os de antes, byte a byte. FASE 7c (P8, §16.5.6, §16.6.9): o tipo etapa sai de _agenda_etapa_frase — ""Instalação de porta fusíveis - distribuição de energia 12v" já está feita", "acrescentar "Trocar a bomba d''água" (no fim, antes de testar e entregar)", "dividir "…" em 3: …". Os outros tipos, os de antes, byte a byte.';

-- agenda_rascunho_gravar (de 20261102100300_agenda_fase7c_conversa.sql)
create or replace function public.agenda_rascunho_gravar(p_autor uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid := public._autor_da_agenda(p_autor);
  v_exp     int;
  v_exp_dia date;
  v_ids     uuid[];
  v_oss_mat uuid[];
  v_r       public.agenda_rascunho%rowtype;
  v_x       uuid;
  v_n       int := 0;
  v_item    text;
  v_estado  text;
  v_msg     text;
  v_linhas  text[] := '{}';
  v_g       record;
  v_p       jsonb;
  v_nome    int;
  -- FASE 2: a hora do *grava* (now(); a bancada fixa com set_config('agenda.agora', …, true), como agenda.hoje), a
  -- config, as frases do que a agenda fez com os pedidos e o tipo de cada linha.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  cf        public.agenda_config := public._agenda_cfg();
  v_f2      text[] := '{}';
  v_f2_item text;
begin
  perform pg_advisory_xact_lock(hashtext('agenda_rascunho:' || v_autor::text));
  -- FASE 7: (7a P10) as frases da peça que voltou a faltar (_agenda_aplicar_material as junta em agenda.material_reabriu)
  -- começam vazias neste *grava*
  perform set_config('agenda.material_reabriu', '', true);
  -- FASE 7: fim

  -- O que passou da validade não grava (e fica marcado, mesmo se o resto falhar).
  with e as (
    update public.agenda_rascunho set estado = 'expirado'
     where autor = v_autor and estado = 'aberto' and expira_em <= now()
    returning criado_em)
  select count(*), max((e.criado_em at time zone 'America/Sao_Paulo')::date) into v_exp, v_exp_dia from e;

  -- FASE 2: primeiro os fatos (Fase 1), depois o andamento, marcar, publicar/decidir e desfazer — cada grupo na ordem em
  -- que o dono falou.
  select coalesce(array_agg(r.id order by case r.tipo when 'andamento' then 1 when 'marcar' then 2 when 'aplicar' then 3
                                                      when 'desfazer' then 4 else 0 end,
                                          (r.dados ->> 'ordem')::int, r.criado_em, r.id), '{}'),
         coalesce(array_agg(distinct r.service_order_id) filter (where r.tipo = 'material'), '{}')
    into v_ids, v_oss_mat
    from public.agenda_rascunho r
   where r.autor = v_autor and r.estado = 'aberto';

  if cardinality(v_ids) = 0 then
    return jsonb_build_object('ok', true, 'gravados', 0, 'expirados', v_exp,
      'texto', case when v_exp > 0 then format('A releitura de %s expirou; me diga de novo o que mudou.', public._dia_curto(v_exp_dia))
                    else 'Não tenho nada esperando para gravar.' end);
  end if;

  -- FASE 2: com a agenda automática fora de 'ligado', o pedido à agenda não grava — e o lote é tudo ou nada.
  -- FASE 3: menos concluir e entregar, que valem em todos os modos (a conclusão pela porta é a correção do D7).
  if cf.modo_proposta <> 'ligado'
     and exists (select 1 from public.agenda_rascunho r where r.id = any (v_ids) and r.tipo in ('marcar', 'aplicar', 'desfazer', 'andamento')
                    and not (r.tipo = 'andamento' and r.dados ->> 'evento' in ('concluiu', 'entregou'))) then
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'motivo', 'em_teste',
      'texto', 'Não gravei nada: a agenda automática ainda está em teste e o que você pediu mexe na agenda. Mande *descarta* e me diga de novo o resto.');
  end if;

  -- Tudo ou nada: um item que não passa desfaz o lote inteiro (as linhas continuam abertas para corrigir).
  begin
    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);   -- as linhas espelho existem antes do fato
    end loop;

    -- O padrão novo de uma pessoa troca, UMA vez antes de entrar o lote, só o que ele realmente troca:
    --   · "vem" (seg a qui): as linhas de padrão dela (do histórico e do dono) que caem em algum desses dias; os
    --     outros dias da semana continuam como estavam;
    --   · "só de manhã", "só à tarde", "não vem" (terça): o "vem" fica; a linha indisponível do turno entra por cima
    --     (a capacidade põe o "não vem neste turno" acima do padrão "vem"). Só sai a restrição que o dono já tinha
    --     dito para os mesmos dias ("só à tarde às terças" e depois "só de manhã às terças").
    update public.agenda_disponibilidade a
       set substituida_em = now()
      from (select (r.dados ->> 'payee_id')::uuid as payee, r.dados ->> 'situacao' as situacao,
                   array(select jsonb_array_elements_text(r.dados -> 'dias_semana')::smallint) as dias
              from public.agenda_rascunho r
             where r.id = any (v_ids) and r.tipo = 'disponibilidade' and (r.dados ->> 'padrao')::boolean) n
     where a.substituida_em is null and a.dias_semana is not null and a.payee_id = n.payee
       and ((n.situacao = 'disponivel' and a.origem in ('historico', 'dono') and a.dias_semana && n.dias)
            or (n.situacao = 'indisponivel' and a.origem = 'dono' and a.situacao = 'indisponivel'
                and a.dias_semana <@ n.dias));

    -- FASE 7b: (7b P2; A4 = NOVO-agenda-55) com a pergunta dos dias fora de desligado (modo_dias), o padrão "vem" novo troca
    -- também o padrão que a própria pessoa (diarista) ou o assistente (agente) disse para os mesmos dias: a palavra mais nova
    -- vence. Desligado, só o histórico e o dono (o de antes).
    if cf.modo_dias <> 'desligado' then
      update public.agenda_disponibilidade a
         set substituida_em = now()
        from (select (r.dados ->> 'payee_id')::uuid as payee, r.dados ->> 'situacao' as situacao,
                     array(select jsonb_array_elements_text(r.dados -> 'dias_semana')::smallint) as dias
                from public.agenda_rascunho r
               where r.id = any (v_ids) and r.tipo = 'disponibilidade' and (r.dados ->> 'padrao')::boolean) n
       where a.substituida_em is null and a.dias_semana is not null and a.payee_id = n.payee
         and n.situacao = 'disponivel' and a.origem in ('diarista', 'agente') and a.dias_semana && n.dias;
    end if;
    -- FASE 7b: fim
    foreach v_x in array v_ids loop
      select * into v_r from public.agenda_rascunho where id = v_x for update;
      v_item := v_r.texto;
      case v_r.tipo
        when 'planejar' then
          perform public._agenda_aplicar_planejar(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'material' then
          perform public._agenda_aplicar_material(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'disponibilidade' then
          perform public._agenda_aplicar_disponibilidade(v_autor, v_r.dados, v_r.trecho, p_hoje);
        -- FASE 4: o prazo do fornecedor vai ao cadastro dele; a frase entra no "Gravado. Agora:" junto dos pedidos.
        when 'fornecedor' then
          v_f2 := v_f2 || public._agenda_aplicar_fornecedor(v_autor, v_r.dados, v_r.trecho, p_hoje);
        -- FASE 4: fim
        -- FASE 4: (P3) "a nota da Correa não é de serviço": a nota, o Pix ou a mensagem respondidos sem OS; a frase entra junto
        -- dos pedidos.
        when 'aviso' then
          v_f2 := v_f2 || public._agenda_aplicar_aviso(v_autor, v_r.dados, v_r.trecho, v_r.canal, p_hoje);
        -- FASE 4: fim
        -- FASE 7c: (7c P4, §5.4) quem faz o quê, o que a OS pede e o responsável: a etiqueta do dono (agenda_etiquetas), o que a OS
        -- pede e o responsável (os_planejamento) e a pergunta habilidade:equipe; a frase entra no "Gravado. Agora:" junto dos pedidos.
        -- Como o fornecedor, grava em qualquer modo da agenda (o modo_proposta só segura os pedidos ao motor, acima).
        when 'habilidade' then
          v_f2 := v_f2 || public._agenda_aplicar_habilidade(v_autor, v_r.dados, v_r.trecho, p_hoje, v_agora);
        -- FASE 7c: fim
        -- FASE 7c: (7c P8, §16.5.6) as etapas de um serviço — feita, falta, não se aplica, a nova e a divisão (os_tarefas, por
        -- _agenda_aplicar_etapa); a frase entra no "Gravado. Agora:" junto dos pedidos. Como o fornecedor e a habilidade, grava em qualquer
        -- modo da agenda (o modo_proposta só segura os pedidos ao motor, acima).
        when 'etapa' then
          v_f2 := v_f2 || public._agenda_aplicar_etapa(v_autor, v_r.dados, v_r.trecho, p_hoje, v_agora);
        -- FASE 7c: fim
        else
          -- FASE 2: o pedido à agenda (marcar, aplicar/decidir, desfazer, andamento) pelas funções do motor.
          v_f2_item := public._agenda_aplicar_pedido(v_autor, v_r.tipo, v_r.service_order_id, v_r.dados, v_r.trecho, v_r.canal,
                                                     p_hoje, v_agora);
          if nullif(btrim(coalesce(v_f2_item, '')), '') is not null then
            v_f2 := v_f2 || v_f2_item;
          end if;
      end case;
      update public.agenda_rascunho set estado = 'gravado', gravado_em = now() where id = v_x;
      v_n := v_n + 1;
    end loop;

    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);
    end loop;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    -- FASE 3: a porta recusou concluir ou entregar (o período fechado no financeiro): a frase dela.
    if v_estado = 'P0096' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', 'Não gravei nada. ' || btrim(v_msg));
    end if;
    -- FASE 2: a agenda recusou um pedido (a proposta ficou velha, a decisão mudou, não coube, já começou…).
    if v_estado = 'P0097' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', format('Não gravei nada. A agenda mudou desde a releitura: %s. Me peça de novo.', rtrim(btrim(v_msg), '.')));
    end if;
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
      'texto', format('Não gravei nada: %s (%s). Corrija o que estiver errado, ou mande *descarta*, e depois *grava* de novo.',
                      case when v_estado = 'P0001' then v_msg else 'o banco recusou um item' end,
                      coalesce(v_item, 'o lote')));
  end;

  -- "Gravado. Agora:" — uma linha por OS (o estado da prontidão) e por pessoa, na ordem em que o dono falou.
  for v_g in
    select r.dados ->> 'grupo' as grupo, min((r.dados ->> 'ordem')::int) as ordem,
           (array_agg(r.service_order_id order by (r.dados ->> 'ordem')::int))[1] as os,
           (array_agg(r.dados order by (r.dados ->> 'ordem')::int))[1] as d,
           string_agg(r.dados ->> 'frase', '; ' order by (r.dados ->> 'ordem')::int) as frases
      from public.agenda_rascunho r
     where r.id = any (v_ids) and r.tipo in ('planejar', 'material', 'disponibilidade')   -- FASE 2: os pedidos vêm em v_f2
     group by r.dados ->> 'grupo'
     order by 2
  loop
    if v_g.os is not null then
      v_p := public.os_prontidao(v_g.os, p_hoje);
      select count(*) into v_nome from public.os_carteira(p_hoje) k where k.cliente_curto = v_p ->> 'cliente_curto';
      v_linhas := v_linhas || ('• ' || public._agenda_rotulo(jsonb_build_object(
                                 'curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero',
                                 'eh_orc', (v_p ->> 'eh_orcamento')::boolean, 'n_nome', v_nome))
                               || ': ' || (v_p ->> 'estado_texto') || '.');
    else
      v_linhas := v_linhas || ('• ' || (v_g.d ->> 'rotulo_grupo') || ': ' || v_g.frases || '.');
    end if;
  end loop;

  -- FASE 7: (7a P10, spec §6.4) a peça que voltou a faltar ("Cerbo GX de Nelson voltou a faltar: o 'compre até' reabriu
  -- (comprando hoje, chega qua 11/11).") entra no "Gravado. Agora:" junto dos pedidos — só com o "compre até" do gestor ligado
  -- (_agenda_aplicar_material só escreve a frase assim); sem isso, nada muda
  v_f2 := v_f2 || coalesce(string_to_array(nullif(current_setting('agenda.material_reabriu', true), ''), E'\n'), '{}'::text[]);
  perform set_config('agenda.material_reabriu', '', true);
  -- FASE 7: fim
  return jsonb_build_object('ok', true, 'gravados', v_n, 'expirados', v_exp,
    'texto', 'Gravado. Agora:' || E'\n' || array_to_string(v_linhas || array(select '• ' || x from unnest(v_f2) x), E'\n')
             || case when v_exp > 0 then E'\n' || format('(A releitura de %s tinha expirado e não foi gravada.)', public._dia_curto(v_exp_dia))
                     else '' end);
end;
$function$;

comment on function public.agenda_rascunho_gravar(uuid, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o *grava* do dono — numa transação, tudo ou nada: marca expirado o que passou da validade; sincroniza o material das OS do lote; troca UMA vez, das pessoas com padrão novo, só os padrões que o "vem" cobre; aplica primeiro os fatos (_agenda_aplicar_planejar/_material/_disponibilidade; Fase 4: _agenda_aplicar_fornecedor, o prazo dito de um fornecedor, que não depende do modo da agenda; Fase 4, P3: _agenda_aplicar_aviso, o "não é de serviço" da nota, do Pix ou da mensagem), depois os pedidos à agenda da Fase 2 na ordem andamento, marcar, aplicar/decidir e desfazer (_agenda_aplicar_pedido: agenda_registrar_dia, a porta, agenda_marcar_os, agenda_aplicar, agenda_decidir, agenda_desfazer, com p_agora = a hora do *grava*); sincroniza de novo. Com modo_proposta fora de ligado, o lote com pedido à agenda não grava (Fase 3: menos concluir e entregar, que gravam em todos os modos; a recusa da porta = "Não gravei nada. Não concluí: …" e o lote volta). Devolve {ok, gravados, expirados, texto "Gravado. Agora:" + uma linha por OS (estado da prontidão), por pessoa e por pedido (a frase da agenda)}; item que não passa: {ok:false, texto "Não gravei nada: …" ou "Não gravei nada. A agenda mudou desde a releitura: …. Me peça de novo.", erro} e nada muda. Chamada só pelo comando sem IA "grava", nunca por ferramenta do modelo. FASE 7 (7a P10, spec §6.4): a frase da peça que voltou a faltar ("Cerbo GX de Nelson voltou a faltar: o ''compre até'' reabriu (comprando hoje, chega qua 11/11).", que _agenda_aplicar_material junta em agenda.material_reabriu só com o "compre até" do gestor ligado) entra no "Gravado. Agora:" junto dos pedidos; a variável começa vazia em cada *grava*. Sem ela, a de antes, byte a byte. Fase 7b (P2; A4 = NOVO-agenda-55): com modo_dias fora de desligado, a troca única do padrão "vem" novo pega também os padrões que a própria pessoa (diarista) ou o assistente (agente) disse para os mesmos dias — a palavra mais nova vence. Desligado, a de antes, byte a byte. FASE 7c (P4, §5.4): o tipo habilidade (quem faz o quê, o que a OS pede, o responsável e o "está certo") aplica por _agenda_aplicar_habilidade, com p_agora = a hora do *grava*, em qualquer modo da agenda (como o fornecedor); a frase entra no "Gravado. Agora:" junto dos pedidos ("Roberto: instala sozinho. O resto ficou como eu marquei: João é ajudante."). Os outros tipos, os de antes, byte a byte. FASE 7c (P8, §16.5.6): o tipo etapa (feita, falta, não se aplica, a nova e a divisão) aplica por _agenda_aplicar_etapa, com p_agora = a hora do *grava*, em qualquer modo da agenda (como o fornecedor e a habilidade); a frase entra no "Gravado. Agora:" junto dos pedidos ("Lenine: "…" feita."). Os outros tipos, os de antes, byte a byte.';

-- _agenda_ver_os (de 20261024160500_agenda_fase1_leituras.sql)
create or replace function public._agenda_ver_os(p_so_id uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c      public.agenda_config := public._agenda_cfg();
  v_p    jsonb := public.os_prontidao(p_so_id, p_hoje);
  v_o    jsonb;
  v_trav text[];
  v_info text[];
  v_pres text;
  l1 text; l2 text; l3 text; l4 text; l5 text; l6 text; l7 text;
  -- FASE 7c: (7c P8) a linha das etapas
  l8 text;
  -- FASE 7c: fim
begin
  if not coalesce((v_p ->> 'ok')::boolean, false) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  v_o := jsonb_build_object('curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero');
  l1 := public._agenda_rotulo(v_o, 'num') || ': ' || (v_p ->> 'estado_texto') || '.';
  v_trav := array(select e ->> 'texto' from jsonb_array_elements(v_p -> 'restricoes') with ordinality t(e, o)
                   where (e ->> 'bloqueia')::boolean order by o);
  if cardinality(v_trav) > 1 then
    l2 := 'O que trava: ' || array_to_string(v_trav, '; ') || case when right(array_to_string(v_trav, '; '), 1) = '?' then '' else '.' end;
  end if;
  l3 := 'Duração: ' || (v_p #>> '{duracao,texto}') || case when right(v_p #>> '{duracao,texto}', 1) = '?' then '' else '.' end;
  v_pres := case v_p #>> '{presenca_dono,presenca}'
    when 'abre_e_fecha' then 'você abre e fecha (não fica o dia todo)'
    when 'sempre' then 'você fica o tempo todo'
    when 'nunca' then 'você não vai'
    else null end;
  if v_pres is not null then
    l4 := 'Presença: ' || v_pres
          || case when v_p #>> '{presenca_dono,fonte}' = 'dono' then ' (você disse)'
                  when v_p #>> '{presenca_dono,motivo}' in ('diagnóstico', 'comissionamento', 'marina nova')
                    then ' (' || (v_p #>> '{presenca_dono,motivo}') || ')'
                  else '' end || '.';
  end if;
  l5 := 'Material: ' || public._agenda_material_resumo(v_p) || case when right(public._agenda_material_resumo(v_p), 1) = '?' then '' else '.' end;
  v_info := array(select e ->> 'texto' from jsonb_array_elements(v_p -> 'restricoes') with ordinality t(e, o)
                   where not (e ->> 'bloqueia')::boolean and e ->> 'tipo' in ('bem', 'nao_antes') order by o);
  if cardinality(v_info) > 0 then
    l6 := 'Também: ' || array_to_string(v_info, '; ') || '.';
  end if;
  if (v_p ->> 'na_carteira')::boolean and v_p ->> 'prazo_efetivo' is not null then
    l7 := 'Prazo: ' || case when (v_p ->> 'prazo_efetivo')::date < p_hoje then 'passou em ' else '' end
          || public._dia_curto((v_p ->> 'prazo_efetivo')::date)
          || case when v_p ->> 'prazo_fonte' = 'dono' then ' (o cliente disse)'
                  else format(' (o meu padrão: %s dias úteis desde a aprovação)', c.prazo_padrao_du) end || '.';
  end if;
  -- FASE 7c: (7c P8, §16.5.5, §16.6.8; R5.2-2(a) e (d)) com modo_tarefas fora de desligado e a OS com etapa, a linha "Etapas: …" depois
  -- da do prazo (os_tarefas_da_os: o feito × pendente; em teste, "Etapas (em teste: a equipe ainda não recebe): …"). Só com a porta das
  -- etapas aberta (o administrador ou o financeiro logado, ou sem login): para quem mais lê a OS, a de antes.
  if c.modo_tarefas <> 'desligado' and (auth.uid() is null or public.is_admin_or_financial(auth.uid()))
     and exists (select 1 from public.os_tarefas t where t.service_order_id = p_so_id and t.estado in ('viva', 'feita', 'nao_se_aplica')) then
    begin
      l8 := public.os_tarefas_da_os(p_so_id, p_hoje) ->> 'texto';
    exception when sqlstate '42501' then
      l8 := null;
    end;
    if l8 is not null then
      return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1, l2, l3, l4, l5, l6, l7, l8], c.texto_max),
        'dados', jsonb_build_object('numero', v_p ->> 'numero', 'estado', v_p ->> 'estado'));
    end if;
  end if;
  -- FASE 7c: fim
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1, l2, l3, l4, l5, l6, l7], c.texto_max),
    'dados', jsonb_build_object('numero', v_p ->> 'numero', 'estado', v_p ->> 'estado'));
end;
$function$;

comment on function public._agenda_ver_os(uuid, date) is
  'Agenda de Produção (Fase 1, P4): a visão de uma OS — o estado, o que trava, a duração, a presença do dono, o material numa linha, o bem/não antes de e o prazo. FASE 7c (P8, §16.5.5, §16.6.8): com modo_tarefas fora de desligado, a OS com etapa e a porta das etapas aberta (o administrador ou o financeiro, ou sem login), a linha "Etapas: …" (os_tarefas_da_os; em teste "Etapas (em teste: a equipe ainda não recebe): …") depois da do prazo. Sem isso, a de antes, byte a byte.';

-- agenda_dia_da_pessoa (de 20261025100500_agenda_fase2_leituras.sql)
create or replace function public.agenda_dia_da_pessoa(p_payee uuid, p_dia date, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  py       record;
  v_dono   boolean;
  v_nome   text;
  v_marc   jsonb;
  v_m      record;
  v_t      record;
  v_sit    text;
  v_dias   int[];
  v_dtxt   text;
  v_fonte  text;
  v_freq   numeric;
  v_nota   text;
  v_abr    constant text[] := array['seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
  v_plu    constant text[] := array['às segundas', 'às terças', 'às quartas', 'às quintas', 'às sextas', 'aos sábados'];
  l1 text; l2 text;
  -- FASE 2: o plano da pessoa no dia
  v_plano  jsonb := '[]'::jsonb;
  v_itens  text[] := '{}';
  r        record;
  e        jsonb;
  v_outros text[];
  -- FASE 7c: (7c P8) o que a pessoa faz em cada OS do dia
  v_p8_tp   jsonb;
  v_p8_its  jsonb;
  v_p8_lst  text;
  -- FASE 7c: fim
begin
  if p_hoje is null or p_dia is null then
    raise exception 'agenda_dia_da_pessoa: sem o dia' using errcode = '22004';
  end if;
  select p.* into py from public.payees p where p.id = p_payee;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei essa pessoa no cadastro.');
  end if;
  v_dono := py.id is not distinct from public._agenda_dono(null) or py.kind = 'socio';
  v_nome := case when v_dono then 'você' else public._agenda_nome_curto(py.name) end;

  if c.modo_proposta = 'ligado' then
    -- FASE 2: em 'ligado' o marcado da pessoa é o plano dela no dia (pelo payee, com ou sem login), com quem mais vai,
    -- e os compromissos com hora do login, se tiver.
    for r in select v.*, (select x from jsonb_array_elements(v.pessoas) x where (x ->> 'payee_id')::uuid = py.id limit 1) as eu
               from public.v_agenda_dia v
              where v.dia = p_dia
                and exists (select 1 from jsonb_array_elements(v.pessoas) x where (x ->> 'payee_id')::uuid = py.id)
              order by v.primeiro_inicio, v.numero, v.service_order_id loop
      v_outros := array(
        select case when coalesce((x ->> 'eh_dono')::boolean, false) then 'você ' else coalesce(x ->> 'nome', 'alguém da equipe') || ' ' end
               || public._agenda_parte_da_pessoa(x)
          from jsonb_array_elements(r.pessoas) with ordinality t(x, o)
         where (x ->> 'payee_id')::uuid is distinct from py.id
         order by o);
      v_itens := v_itens || (coalesce(r.cliente_curto || ' (' || r.numero || ')', r.numero) || ' '
                             || public._agenda_parte_da_pessoa(r.eu || jsonb_build_object('eh_dono', v_dono))
                             || case when r.reserva then ', reserva' else '' end
                             || coalesce(' (com ' || nullif(public._agenda_lista(v_outros, null), '') || ')', ''));
      v_plano := v_plano || jsonb_build_object('os', r.service_order_id, 'numero', r.numero, 'hora',
                                               to_char(r.primeiro_inicio at time zone 'America/Sao_Paulo', 'HH24:MI'),
                                               'turnos', r.eu -> 'turnos', 'presenca', r.eu ->> 'presenca', 'reserva', r.reserva);
      -- FASE 7c: (7c P8, §16.5.5, §16.6.8; R5.2-2(a)) com modo_tarefas fora de desligado e a porta das etapas aberta, o item da OS ganha
      -- " — o que fazer: …" (o que ela faz naquela OS no dia, _agenda_tarefas_da_pessoa: 3 linhas, o item inteiro em até 200 letras; a
      -- etapa final com você: "— com você") e o plano ganha as etapas. Sem etapa: a de antes.
      if c.modo_tarefas <> 'desligado' and not r.reserva and (auth.uid() is null or public.is_admin_or_financial(auth.uid())) then
        if v_p8_tp is null then
          v_p8_tp := public._agenda_tarefas_da_pessoa(py.id, p_dia, p_hoje);
        end if;
        v_p8_its := (select jsonb_agg(i || jsonb_build_object('com', case when (i ->> 'com_dono')::boolean then 'você' end)
                                      order by (i ->> 'n')::int)
                       from jsonb_array_elements(coalesce(v_p8_tp -> 'itens', '[]'::jsonb)) i
                      where i ->> 'os' = r.service_order_id::text);
        if v_p8_its is not null then
          v_p8_lst := public._agenda_tarefas_lista_texto(v_p8_its, 3,
                        greatest(200 - char_length(v_itens[cardinality(v_itens)]) - char_length(' — o que fazer: '), 40));
          v_itens[cardinality(v_itens)] := v_itens[cardinality(v_itens)] || ' — o que fazer: ' || v_p8_lst;
          v_plano := jsonb_set(v_plano, array[(jsonb_array_length(v_plano) - 1)::text],
                               (v_plano -> -1) || jsonb_build_object('etapas', v_p8_its));
        end if;
      end if;
      -- FASE 7c: fim
    end loop;
    if py.app_user_id is not null then
      for e in select x from jsonb_array_elements(public._agenda_marcados(p_dia, p_dia, p_hoje, null, py.app_user_id)) x
                where x ->> 'tipo' = 'compromisso' loop
        v_itens := v_itens || (e ->> 'texto_dia');
      end loop;
    end if;
    v_marc := v_plano;
  else
    v_marc := case when py.app_user_id is null then '[]'::jsonb
                   else public._agenda_marcados(p_dia, p_dia, p_hoje, case when v_dono then null else py.app_user_id end,
                                                py.app_user_id) end;
    v_itens := array(select x ->> 'texto_dia' from jsonb_array_elements(v_marc) with ordinality t(x, o) order by o);
  end if;

  -- A situação do dia pela grade (manhã e tarde).
  select bool_and(g.situacao = 'fim_de_semana') as fds, bool_and(g.situacao = 'feriado') as fer,
         bool_and(g.situacao = 'indisponivel') as indisp, bool_or(g.situacao = 'indisponivel') as meio_indisp,
         bool_and(g.situacao = 'sem_padrao') as sem,
         max(g.motivo) filter (where g.situacao in ('fim_de_semana', 'feriado')) as motivo_cal,
         max(g.motivo) filter (where g.situacao = 'indisponivel') as motivo_ind,
         bool_or(g.situacao = 'indisponivel' and g.turno = 'manha') as manha_ind,
         count(*) as n
    into v_t
    from public.agenda_capacidade(p_dia, p_dia, p_hoje) g
   where g.payee_id = py.id;

  -- O padrão: os dias da semana em que a pessoa costuma vir (o que está em vigor em agenda_disponibilidade).
  v_dias := array(select distinct x from public.agenda_disponibilidade d, unnest(d.dias_semana) x
                   where d.payee_id = py.id and d.substituida_em is null and d.periodo is null
                     and d.situacao in ('disponivel', 'confirmada') and d.turno is null
                   order by x);

  v_sit := case
    when coalesce(v_t.n, 0) = 0 then
      case when extract(isodow from p_dia) = 7 then 'domingo'
           when extract(isodow from p_dia) = 6 and not c.sabado_util then 'sábado só quando vocês combinam'
           when public.agenda_feriado(p_dia) is not null then 'é feriado (' || public.agenda_feriado(p_dia) || ')'
           else null end
    when v_t.fds then v_t.motivo_cal
    when v_t.fer then 'é feriado (' || v_t.motivo_cal || ')'
    when v_t.indisp then case when v_dono then 'você não fica em campo' else 'não vem' end
                         || coalesce(' (' || nullif(v_t.motivo_ind, 'não vem') || ')', '')
    when v_t.meio_indisp then case when v_t.manha_ind then 'só à tarde' else 'só de manhã' end
    -- Tem padrão em outros dias e não neste: "às segundas não costuma vir" (o "não sei" fica para quem não tem padrão).
    when v_t.sem and not v_dono and cardinality(v_dias) > 0
         and not (extract(isodow from p_dia)::int = any (v_dias)) and extract(isodow from p_dia) between 1 and 6
      then v_plu[extract(isodow from p_dia)::int] || ' não costuma vir'
    when v_t.sem and not v_dono then 'não sei se vem: não há padrão de dias'
    else null end;

  -- FASE 2: o texto sai de v_itens (o plano e os compromissos em 'ligado'; o marcado de sempre fora dele)
  if cardinality(v_itens) = 0 then
    l1 := public._agenda_dia_rotulo(p_dia, p_hoje) || ', ' || v_nome || ' não tem nada marcado';
  else
    l1 := public._agenda_dia_rotulo(p_dia, p_hoje) || ', ' || v_nome || ' tem ' || public._agenda_lista(v_itens, 5);
  end if;
  l1 := l1 || coalesce(' — ' || v_sit, '') || '.';

  select case when bool_and(d.origem = 'historico') then format('pelas diárias das últimas %s semanas', c.medicao_semanas)
              when bool_or(d.origem = 'dono') then 'você disse'
              else 'combinado' end
    into v_fonte
    from public.agenda_disponibilidade d
   where d.payee_id = py.id and d.substituida_em is null and d.periodo is null and d.situacao in ('disponivel', 'confirmada');
  select d.frequencia, d.nota into v_freq, v_nota
    from public.agenda_disponibilidade d
   where d.payee_id = py.id and d.substituida_em is null and d.periodo is null and d.origem = 'historico'
     and d.dias_semana @> array[extract(isodow from p_dia)::smallint]
   order by d.criado_em desc, d.id desc limit 1;

  if cardinality(v_dias) = 0 then
    l2 := case when v_dono then 'Você ainda não disse quais dias fica em campo.'
               else 'Não sei os dias em que costuma vir: não há diárias recentes.' end;
  else
    v_dtxt := case
      when cardinality(v_dias) = 1 then 'só ' || v_plu[v_dias[1]]
      when v_dias[cardinality(v_dias)] - v_dias[1] + 1 = cardinality(v_dias) and cardinality(v_dias) >= 3 then
        format('de %s a %s', v_abr[v_dias[1]], v_abr[v_dias[cardinality(v_dias)]])
      else public._agenda_lista(array(select v_abr[x] from unnest(v_dias) x), null) end;
    l2 := case when v_dono then 'Você costuma ficar em campo ' else 'Costuma vir ' end || v_dtxt
          || ' (' || v_fonte
          || case when v_freq is not null and v_freq < 1 and v_nota ~ '[0-9]+(,[0-9]+)? de [0-9]+ '
                  then ': ' || (regexp_match(v_nota, '([0-9]+(,[0-9]+)? de [0-9]+ [^ (]+)'))[1] else '' end
          || ').';
  end if;

  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1 || ' ' || l2], c.texto_max),
    'dados', jsonb_build_object('pessoa', v_nome, 'dia', p_dia, 'marcados', v_marc, 'situacao', v_sit, 'dias_semana', v_dias)
             -- FASE 2: o plano da pessoa no dia
             || case when c.modo_proposta = 'ligado' then jsonb_build_object('plano', v_plano) else '{}'::jsonb end);
end;
$function$;

comment on function public.agenda_dia_da_pessoa(uuid, date, date) is
  'Agenda de Produção (Fase 1, P4; Fase 2, P5): "o que o Roberto faz amanhã?" — o marcado da pessoa no dia (fora de ''ligado'': OS em que é técnica, compromisso com hora; em ''ligado'': o plano dela pelo payee, com ou sem login, e quem mais vai — "Qua 04/11, Roberto tem Vanderlei (OS-00069) o dia todo (com você abrindo)" — e os compromissos do login), a situação pela grade (sábado só quando vocês combinam, domingo, feriado, não vem, só de manhã/à tarde, sem padrão) e o padrão de dias ("costuma vir de seg a sex (pelas diárias das últimas 8 semanas: 3 de 5 segundas)"). Sem artigo de gênero antes do nome. {ok, texto, dados}. FASE 7c (P8, §16.5.5, §16.6.8): em ligado, com modo_tarefas fora de desligado e a porta das etapas aberta, o item de cada OS ganha " — o que fazer: …" (o que a pessoa faz nela no dia: _agenda_tarefas_da_pessoa, 3 linhas, o item em até 200 letras; "— com você" na etapa final com o dono) e o plano ganha etapas. Sem etapa, a de antes, byte a byte.';

-- agenda_equipe_ficha (de 20261026100300_agenda_fase3_equipe_diarias.sql)
create or replace function public.agenda_equipe_ficha(p_payee uuid, p_dia date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_nome    text;
  v_dono    uuid := public._agenda_dono(null);
  v_gustavo text;
  v_dia_txt text;
  v_ref     text;
  r         record;
  v_quem    text[];
  v_parte   text;
  v_partes  text[] := '{}';
  v_resp    text[] := '{}';
  v_conf    text[] := '{}';
  v_os      jsonb := '[]'::jsonb;
  v_m       boolean := false;
  v_t       boolean := false;
  v_serv    text;
  v_n       int := 0;
  -- FASE 7c: (7c P8) o que fazer, na ficha
  v_p8_tp    jsonb;
  v_p8_its   jsonb;
  v_p8_lst   text;
  v_p8_cob   text;
  v_p8_ficha text;
  v_p8_cf    text;
  v_p8_curto text;
  v_p8_hoje  text;
  v_p8_perg  jsonb;
  v_p8_k     int;
  v_p8_suf   text;
  -- FASE 7c: fim
begin
  if p_payee is null or p_dia is null or p_hoje is null then
    raise exception 'Faltam a pessoa e o dia da ficha.' using errcode = '22023';
  end if;
  select public._agenda_nome_curto(p.name) into v_nome from public.payees p where p.id = p_payee;
  v_gustavo := coalesce('o ' || (select public._agenda_nome_curto(p.name) from public.payees p where p.id = v_dono), 'o responsável');
  v_dia_txt := public._agenda_dia_da_equipe(p_dia, p_hoje);
  v_ref := case when p_dia = p_hoje then 'hoje' when p_dia = p_hoje + 1 then 'amanhã' else v_dia_txt end;

  if cf.modo_proposta = 'ligado' then
    for r in
      select a.service_order_id as os, min(lower(a.periodo)) as ini, bool_or(a.turno = 'manha') as m, bool_or(a.turno = 'tarde') as t,
             array_agg(distinct a.turno) as turnos
        from public.agenda_alocacoes a
       where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       group by a.service_order_id
       order by 2, 1
    loop
      v_n := v_n + 1;
      v_m := v_m or r.m;
      v_t := v_t or r.t;
      -- com quem: as outras pessoas da mesma OS nos mesmos turnos (o dono pela abertura ou o fechamento também), "o X"
      v_quem := array(
        select 'o ' || x.nome
          from (select distinct on (b.payee_id) b.payee_id, public._agenda_nome_curto(py.name) as nome,
                       b.payee_id = v_dono or py.kind = 'socio' as dono
                  from public.agenda_alocacoes b join public.payees py on py.id = b.payee_id
                 where b.service_order_id = r.os and b.dia = p_dia and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                   and b.payee_id <> p_payee and b.turno = any (r.turnos)) x
         order by x.dono desc, x.nome, x.payee_id);
      v_parte := public._agenda_hora_curta(r.ini) || ' ' || public._agenda_bem_da_os(r.os)
                 || coalesce(', ' || public._agenda_local_da_os(r.os), '')
                 || case when cardinality(v_quem) > 0 then ', com ' || public._agenda_lista(v_quem, null) else '' end;
      v_partes := v_partes || v_parte;
      v_resp := v_resp || (v_parte || ', ' || case when r.m and r.t then 'o dia todo' when r.m then 'só de manhã' else 'só à tarde' end);
      v_conf := v_conf || (coalesce(public._agenda_nome_curto((select cl.name from public.service_orders so
                                                                  join public.clients cl on cl.id = so.client_id where so.id = r.os)),
                                    'o serviço') || ' às ' || public._agenda_hora_curta(r.ini));
      v_os := v_os || jsonb_build_object('os', r.os, 'inicio', r.ini, 'manha', r.m, 'tarde', r.t);
    end loop;
  end if;

  if v_n = 0 then
    return jsonb_build_object('tem_plano', false, 'turnos', '[]'::jsonb, 'os', '[]'::jsonb,
      'texto_ficha', null, 'texto_confirmar', null, 'texto_curto', null, 'texto_como_foi', null,
      'texto_resposta', case
        when extract(isodow from p_dia) = 7 then public._agenda_maiuscula(v_ref) || ' é domingo: não tem serviço marcado.'
        when not public.agenda_dia_util(p_dia) then public._agenda_maiuscula(v_dia_txt) || ' não tem serviço marcado.'
        else format('Ainda não tenho o plano de %s. Vou ver com %s e te falo.', v_ref, v_gustavo) end);
  end if;

  -- FASE 7c: (7c P8, §16.5.7, §16.6.1–16.6.3; AG7-10, AG7-10e) com modo_tarefas ligado e o que fazer no dia (_agenda_tarefas_da_pessoa):
  -- a ficha troca o "Serviço: …" por "O que fazer: 1) …; 2) …" (tarefas_linhas_max linhas, 300 letras; a ficha inteira em até 440, para
  -- o acesso do 7d e o previsto do 7f caberem nos 600 da fila) e, a quem responde por uma OS no último dia dela ou no dia do prazo
  -- (tarefas_cobrar_vespera), "É o último dia no barco do Lenine: tem que ficar tudo pronto." (e o que sobra, até 2); o "como foi" de quem
  -- responde ganha a lista do que devia ficar pronto hoje (sem prefixo; até 330 letras); a ficha que vai junto do "como foi"
  -- (texto_curto) ganha "O que fazer" (3 linhas) só quando os dois cabem em 590 letras; o "o que tem pra amanhã" ganha "O que fazer" (8
  -- linhas). Desligado, em teste ou sem etapa: a de antes, byte a byte. O texto_confirmar nunca muda.
  if cf.modo_tarefas = 'ligado' then
    v_p8_tp := public._agenda_tarefas_da_pessoa(p_payee, p_dia, p_hoje);
  end if;
  if coalesce((v_p8_tp ->> 'tem')::boolean, false) then
    v_p8_its := (select jsonb_agg(i || jsonb_build_object('com', case when (i ->> 'com_dono')::boolean then v_gustavo end,
                                                          'rotulo', case when (v_p8_tp ->> 'duas_os')::boolean then i ->> 'cliente' end)
                                  order by (i ->> 'n')::int)
                   from jsonb_array_elements(v_p8_tp -> 'itens') i);
    -- a cobrança: a OS do último dia (ou do prazo) pela qual ela responde
    select string_agg(format(' É %s %s: tem que ficar tudo pronto.', case when u.k = 'ultimo' then 'o último dia' else 'o dia do prazo' end,
                             u.bem)
                      || case when jsonb_array_length(u.sobra) > 0
                              then ' Ainda falta: ' || public._agenda_lista(array(select x from jsonb_array_elements_text(u.sobra)
                                                                                    with ordinality s(x, o) where s.o <= 2 order by s.o), null) || '.'
                              else '' end, '' order by u.o)
      into v_p8_cob
      from (select distinct on (z.e ->> 'os') z.e ->> 'os' as os, z.e ->> 'bem' as bem, coalesce(z.e -> 'sobra', '[]'::jsonb) as sobra, z.k, z.o
              from (select e, 'ultimo'::text as k, o from jsonb_array_elements(v_p8_tp -> 'ultimo_dia') with ordinality t(e, o)
                    union all
                    select e, 'prazo'::text as k, 100 + o from jsonb_array_elements(v_p8_tp -> 'prazo') with ordinality t(e, o)) z
             where cf.tarefas_cobrar_vespera and (v_p8_tp -> 'responde') ? (z.e ->> 'os')
             order by z.e ->> 'os', z.o) u;
    v_p8_k := cf.tarefas_linhas_max;
    loop
      v_p8_lst := public._agenda_tarefas_lista_texto(v_p8_its, v_p8_k, 300);
      v_p8_ficha := format('%s, %s: %s.', v_nome, v_dia_txt, array_to_string(v_partes, '; ')) || ' O que fazer: ' || v_p8_lst || '.'
                    || coalesce(v_p8_cob, '') || ' Responde OK se tá certo.';
      exit when char_length(v_p8_ficha) <= 440 or v_p8_k = 1;
      v_p8_k := v_p8_k - 1;
    end loop;
    -- o "como foi" de quem responde: o que devia ficar pronto hoje (os números do dia)
    v_p8_perg := coalesce(v_p8_tp -> 'pergunta', '[]'::jsonb);
    v_p8_cf := 'Como foi hoje? ' || case when v_m and v_t then 'Ficou manhã e tarde?' when v_m then 'Ficou a manhã?' else 'Ficou a tarde?' end;
    if jsonb_array_length(v_p8_perg) = 1 then
      v_p8_cf := v_p8_cf || format(' Do de hoje: %s. Se ficou pronto, responde OK. Se faltou, responde: ok, faltou.',
                                   public._agenda_tarefas_lista_texto(v_p8_perg, 1, 200, false));
    elsif jsonb_array_length(v_p8_perg) > 1 then
      v_p8_suf := format('. Se fez tudo, responde OK. Se faltou alguma, responde OK e o número (ex.: ok, faltou a %s).', v_p8_perg -> -1 ->> 'n');
      v_p8_cf := v_p8_cf || ' Do de hoje: '
                 || public._agenda_tarefas_lista_texto(v_p8_perg, 8, 330 - char_length(v_p8_cf) - char_length(' Do de hoje: ')
                                                                       - char_length(v_p8_suf), false)
                 || v_p8_suf;
    else
      v_p8_cf := v_p8_cf || ' Terminou o previsto? Se foi tudo como o previsto, responde OK.';
    end if;
    -- a ficha que vai junto do "como foi" de hoje: com "O que fazer" só quando os dois cabem em 590 letras
    v_p8_curto := format('%s: %s.', public._agenda_maiuscula(v_dia_txt), array_to_string(v_partes, '; '));
    v_p8_hoje := case when p_dia = p_hoje then v_p8_cf
                      else public.agenda_equipe_ficha(p_payee, p_hoje, p_hoje) ->> 'texto_como_foi' end;
    v_p8_lst := public._agenda_tarefas_lista_texto(v_p8_its, 3,
                  590 - coalesce(char_length(v_p8_hoje), 0) - 1 - char_length(v_p8_curto) - char_length(' O que fazer: .'));
    if v_p8_lst is not null and coalesce(char_length(v_p8_hoje), 0) + 1 + char_length(v_p8_curto || ' O que fazer: ' || v_p8_lst || '.') <= 590
       and char_length(v_p8_lst) >= 20 then
      v_p8_curto := v_p8_curto || ' O que fazer: ' || v_p8_lst || '.';
    end if;
    return jsonb_build_object(
      'tem_plano', true,
      'turnos', to_jsonb(array_remove(array[case when v_m then 'manha' end, case when v_t then 'tarde' end], null)),
      'os', v_os,
      'texto_ficha', v_p8_ficha,
      'texto_resposta', format('%s, %s: %s.', v_nome, v_dia_txt, array_to_string(v_resp, '; '))
                        || ' O que fazer: ' || public._agenda_tarefas_lista_texto(v_p8_its, 8, 400) || '.'
                        || format(' Dúvida, fala com %s.', v_gustavo),
      'texto_confirmar', format('Bom dia, %s. Hoje é %s. Tá confirmado?', v_nome, public._agenda_lista(v_conf, null)),
      'texto_curto', v_p8_curto,
      'texto_como_foi', v_p8_cf,
      'tarefas', v_p8_tp);
  end if;
  -- FASE 7c: fim
  v_serv := case when v_n = 1 then public._agenda_servico_curto((v_os -> 0 ->> 'os')::uuid) end;
  return jsonb_build_object(
    'tem_plano', true,
    'turnos', to_jsonb(array_remove(array[case when v_m then 'manha' end, case when v_t then 'tarde' end], null)),
    'os', v_os,
    'texto_ficha', format('%s, %s: %s.', v_nome, v_dia_txt, array_to_string(v_partes, '; '))
                   || coalesce(' Serviço: ' || v_serv || '.', '') || ' Responde OK se tá certo.',
    'texto_resposta', format('%s, %s: %s. Dúvida, fala com %s.', v_nome, v_dia_txt, array_to_string(v_resp, '; '), v_gustavo),
    'texto_confirmar', format('Bom dia, %s. Hoje é %s. Tá confirmado?', v_nome, public._agenda_lista(v_conf, null)),
    'texto_curto', format('%s: %s.', public._agenda_maiuscula(v_dia_txt), array_to_string(v_partes, '; ')),
    'texto_como_foi', 'Como foi hoje? ' || case when v_m and v_t then 'Ficou manhã e tarde?' when v_m then 'Ficou a manhã?'
                                                else 'Ficou a tarde?' end
                      || ' Terminou o previsto? Se foi tudo como o previsto, responde OK.');
end;
$function$;

comment on function public.agenda_equipe_ficha(uuid, date, date) is
  'Agenda de Produção (Fase 3, P4): a ficha de uma pessoa num dia, só do publicado (alocações vigentes sem reserva, com modo_proposta ligado; fora disso tem_plano = false) — {tem_plano, turnos, os[{os, inicio, manha, tarde}], texto_ficha ("Roberto, terça (03/11): 8h no barco do Vanderlei, com o Gustavo. Serviço: … Responde OK se tá certo."), texto_resposta (o "o que tem pra amanhã", com o turno; sem plano "Ainda não tenho o plano de amanhã. Vou ver com o Gustavo e te falo."; domingo "Amanhã é domingo: não tem serviço marcado."), texto_confirmar ("Bom dia, Roberto. Hoje é Vanderlei às 8h. Tá confirmado?"), texto_curto (a ficha que vai junto do "como foi hoje?") e texto_como_foi}. Nunca valor, número de OS, cliente de outra pessoa nem acesso. Só service_role. FASE 7c (P8, §16.5.7, §16.6.1–16.6.3; AG7-10): com modo_tarefas ligado e etapas no dia (_agenda_tarefas_da_pessoa), texto_ficha troca o "Serviço: …" por "O que fazer: 1) …; 2) …" (tarefas_linhas_max linhas, 300 letras; a ficha em até 440) e, a quem responde por uma OS no último dia dela ou no dia do prazo (tarefas_cobrar_vespera), "É o último dia no barco do Lenine: tem que ficar tudo pronto." (e "Ainda falta: …", até 2); texto_como_foi de quem responde: "Do de hoje: 1) …. Se fez tudo, responde OK. Se faltou alguma, responde OK e o número (ex.: ok, faltou a 3)." (com 1: "Se ficou pronto, responde OK. Se faltou, responde: ok, faltou."); texto_curto com "O que fazer" (3 linhas) só quando cabe junto do "como foi" de hoje em 590 letras; texto_resposta com "O que fazer" (8 linhas) antes do "Dúvida, fala com …"; a saída ganha tarefas. Desligado, em teste ou sem etapa: a de antes, byte a byte; o texto_confirmar nunca muda.';

-- _agenda_rotina_conclusao (de 20261026100300_agenda_fase3_equipe_diarias.sql)
create or replace function public._agenda_rotina_conclusao(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       record;
  v_os    uuid[];
  v_x     uuid;
  v_st    text;
  v_fut   date[];
  v_rest  numeric;
  v_r     jsonb;
  v_acao  uuid;
  v_nome  text;
  v_cli   text;
  v_conc  int := 0;
  v_perg  int := 0;
  -- FASE 7c: (7c P8) as etapas pendentes ditas da OS
  v_p8_pend text[];
  -- FASE 7c: fim
begin
  for m in
    select x.* from public.agenda_equipe_mensagens x
     where x.tipo = 'como_foi' and x.modo = 'ligado' and x.dia = p_hoje and x.acao_id is null
       and coalesce((x.leitura ->> 'terminou')::boolean, false)
     order by x.resposta_em, x.id
  loop
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = m.payee_id and a.dia = p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva');
    continue when cardinality(v_os) <> 1;
    v_x := v_os[1];
    select so.status into v_st from public.service_orders so where so.id = v_x;
    continue when v_st not in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client');
    v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = m.payee_id);
    v_cli := (select public._agenda_nome_curto(cl.name) from public.service_orders so join public.clients cl on cl.id = so.client_id
               where so.id = v_x);
    v_fut := array(select distinct a.dia from public.agenda_alocacoes a
                    where a.service_order_id = v_x and a.dia > p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    order by 1);
    v_rest := (public.agenda_meios_da_os(v_x, p_hoje + 1) ->> 'restantes')::numeric;
    -- FASE 7c: (7c P8, §16.3.9 (c), §16.6.6; AG7-10d; R5.2-3, R5.10-11) com modo_tarefas ligado e tarefas_concluir_sem_pendente, o
    -- "terminei" no último dia não conclui a OS que tem etapa pendente DITA (uma etapa viva cuja última linha com resultado é pendente: pela
    -- equipe, pela conferência ou pelo dono); vira a pergunta concluir com o que falta. A sem registro e a etapa sem linha não seguram. O
    -- *concluiu* do dono conclui como hoje.
    if cardinality(v_fut) = 0 and v_rest = 0 and cf.modo_tarefas = 'ligado' and cf.tarefas_concluir_sem_pendente then
      v_p8_pend := array(select t.texto from public.os_tarefas t
                          where t.service_order_id = v_x and t.estado = 'viva'
                            and (select d.resultado from public.os_tarefas_dia d
                                  where d.tarefa_id = t.id and d.estado = 'planejada' and d.termina and d.resultado is not null
                                  order by d.dia desc, d.turno = 'tarde' desc, d.resultado_em desc limit 1) = 'pendente'
                          order by t.ordem, t.id);
      if cardinality(v_p8_pend) > 0 then
        if public._agenda_equipe_perguntar('concluir', format('concluir:%s:%s', v_x, p_hoje), m.payee_id, v_x, p_hoje,
             format('O %s disse que terminou o %s, mas não concluí: ainda falta %s. *concluiu %s* fecha a OS mesmo assim.', v_nome,
                    coalesce(v_cli, public._agenda_rotulo_da_os(v_x)),
                    public._agenda_lista(array(select '"' || x || '"' from unnest(v_p8_pend) with ordinality u(x, o) order by o), 3),
                    coalesce(v_cli, (select so.service_order_number from public.service_orders so where so.id = v_x))),
             'ligado', p_agora) then
          v_perg := v_perg + 1;
        end if;
        continue;
      end if;
    end if;
    -- FASE 7c: fim
    if cardinality(v_fut) = 0 and v_rest = 0 then
      if cf.modo_proposta = 'ligado' then
        v_r := public.os_registrar_marco(v_x, 'conclusao', 'equipe', null, null,
                                         left(format('O %s disse que terminou: "%s"', v_nome, m.resposta_texto), 200), p_hoje, p_agora);
        if coalesce((v_r ->> 'ok')::boolean, false) and v_r ->> 'acao_id' is not null then
          update public.agenda_equipe_mensagens set acao_id = (v_r ->> 'acao_id')::uuid where id = m.id;
          v_conc := v_conc + 1;
        else
          -- a porta recusou (o período fechado, o levantamento…): a pergunta, com a frase dela
          perform public._agenda_equipe_perguntar('concluir', format('concluir:%s:%s', v_x, p_hoje), m.payee_id, v_x, p_hoje,
            format('O %s disse que terminou o %s, mas não concluí: %s', v_nome, public._agenda_rotulo_da_os(v_x),
                   coalesce(v_r ->> 'texto', 'a porta recusou.')), 'ligado', p_agora);
          v_perg := v_perg + 1;
        end if;
      else
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
        values (clock_timestamp(), p_hoje, false, 'equipe', 'concluir', v_x, array[v_x], m.payee_id,
                jsonb_build_object('mensagem', m.id),
                left(format('Em teste: concluiria o %s (o %s disse que terminou e era o último dia do plano).',
                            public._agenda_rotulo_da_os(v_x), v_nome), 400))
        returning id into v_acao;
        update public.agenda_equipe_mensagens set acao_id = v_acao where id = m.id;
        v_conc := v_conc + 1;
      end if;
    else
      if public._agenda_equipe_perguntar('concluir', format('concluir:%s:%s', v_x, p_hoje), m.payee_id, v_x, p_hoje,
           format('O %s disse que terminou o %s, mas o plano tinha mais %s. *concluiu %s* fecha a OS.', v_nome,
                  public._agenda_rotulo_da_os(v_x),
                  case when cardinality(v_fut) > 0
                       then public._agenda_plural(cardinality(v_fut), 'dia', 'dias') || ' (' || public._agenda_dias_texto(v_fut) || ')'
                       else 'serviço do que você disse' end,
                  coalesce(v_cli, (select so.service_order_number from public.service_orders so where so.id = v_x))),
           'ligado', p_agora) then
        v_perg := v_perg + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('concluidas', v_conc, 'perguntas', v_perg);
end;
$function$;

comment on function public._agenda_rotina_conclusao(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a conclusão pelo técnico — o "terminei" do "como foi" de hoje sem mais dia no plano conclui pela porta (via equipe; modo_proposta ligado; em sombra só registra); fora do último dia, a pergunta concluir. FASE 7c (P8, §16.3.9 (c), §16.6.6; AG7-10d; R5.2-3): com modo_tarefas ligado e tarefas_concluir_sem_pendente, a OS com etapa pendente dita (uma etapa viva cuja última linha com resultado é pendente) não conclui: a pergunta concluir "O Alex disse que terminou o Lenine, mas não concluí: ainda falta "Passagem e crimpagem de cabos de bateria". *concluiu Lenine* fecha a OS mesmo assim."; a sem registro e a etapa sem linha não seguram. Fora disso, a de antes, byte a byte.';

-- agenda_resposta_da_equipe (de 20261101100800_agenda_fase77b_correcao.sql)
create or replace function public.agenda_resposta_da_equipe(p_phone text, p_body text, p_message_id text,
                                                            p_recebida_em timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_hoje   date := (p_recebida_em at time zone 'America/Sao_Paulo')::date;
  v_hora   time := (p_recebida_em at time zone 'America/Sao_Paulo')::time;
  v_ids    uuid[];
  v_payee  uuid;
  v_nome   text;
  v_l      jsonb;
  v_tipo   text;
  m        public.agenda_equipe_mensagens%rowtype;
  v_recibo timestamptz;
  v_trecho text := left(btrim(coalesce(p_body, '')), 500);
  v_wa     text := nullif(btrim(coalesce(p_message_id, '')), '');
  v_dia    date;
  v_f      jsonb;
  v_r      jsonb;
  v_os     uuid[];
  v_disp   uuid;
  v_rep    jsonb;
  v_acao   uuid;
  v_plano  text[];
  v_ditos  text[];
  v_conf   text[];
  v_term   boolean;
  v_ent    boolean;
  v_estado text;
  v_msg    text;
  v_resp   text;
  v_div    boolean;
  -- FASE 7b: (7b P3, §5.2; A1, A3) a pergunta dos dias da semana: a mensagem aberta dela, a leitura, a gravação e a resposta
  v_7b_mq   public.agenda_equipe_mensagens%rowtype;
  v_7b_vd   jsonb;
  v_7b_g    jsonb;
  v_7b_resp text;
  v_7b_ult  boolean;
  v_7b_sem  text;
  v_7b_dias smallint[];
  v_7b_sab  boolean;
  -- FASE 7b: fim
  -- FASE 7c: (7c P8) as etapas no "como foi"
  v_p8_dp    jsonb;
  v_p8_lista jsonb;
  v_p8_lt    jsonb;
  v_p8_its   jsonb;
  v_p8_parc  jsonb := '{}'::jsonb;
  v_p8_conf  text[];
  v_p8_os    text;
  v_p8_tu    text[];
  -- FASE 7c: fim
begin
  if v_trecho = '' or p_recebida_em is null then
    return jsonb_build_object('consumiu', false);
  end if;
  -- desligado: nada lê (o webhook segue como sempre)
  if cf.modo_equipe = 'desligado' then
    return jsonb_build_object('consumiu', false, 'modo', 'desligado');
  end if;
  v_ids := public._agenda_payees_do_telefone(p_phone, v_hoje);
  if cardinality(v_ids) > 1 then
    perform public.log_app_error('db', 'agenda: o telefone de uma mensagem é de mais de uma pessoa da equipe; não li a resposta',
                                 'agenda', 'equipe:telefone', 'warn', jsonb_build_object('payees', to_jsonb(v_ids)));
    return jsonb_build_object('consumiu', false, 'motivo', 'ambiguo');
  end if;
  if cardinality(v_ids) = 0 then
    return jsonb_build_object('consumiu', false);
  end if;
  v_payee := v_ids[1];
  v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = v_payee);
  -- a mesma mensagem dele de novo: nada muda
  if v_wa is not null and exists (select 1 from public.agenda_equipe_mensagens x
                                   where x.payee_id = v_payee and (x.resposta_wa_id = v_wa or x.responde_wa_id = v_wa)) then
    return jsonb_build_object('consumiu', exists (select 1 from public.agenda_equipe_mensagens x
                                                   where x.payee_id = v_payee and x.modo = 'ligado'
                                                     and (x.resposta_wa_id = v_wa or x.responde_wa_id = v_wa)),
                              'repetida', true);
  end if;

  -- FASE 7b: (7b P3, §5.2 item 1) a pergunta dos dias da semana aberta — ligada, enfileirada, mandada antes desta mensagem e com o
  -- prazo da semana por vir (a quinta que planeja a semana, hora_do_plano − equipe_dias_fechar_antes) — e a leitura dela, sem IA. Só
  -- com a pergunta dos dias ligada (modo_dias): em teste ela nunca sai, e nada daqui muda.
  if cf.modo_dias = 'ligado' then
    select * into v_7b_mq from public.agenda_equipe_mensagens x
     where x.payee_id = v_payee and x.tipo = 'dias' and x.modo = 'ligado' and x.estado = 'enfileirada'
       and x.enviar_em <= p_recebida_em
       and p_recebida_em < (((x.dia - 7 + (cf.dia_do_plano - 1)) + cf.hora_do_plano) - cf.equipe_dias_fechar_antes)
                           at time zone 'America/Sao_Paulo'
     order by x.enviar_em desc, x.criada_em desc limit 1;
    if v_7b_mq.id is not null then
      v_7b_vd := public._agenda_ler_dias_da_equipe(p_body);
    end if;
  end if;
  -- FASE 7b: fim
  v_l := public._agenda_ler_resposta_da_equipe(p_body);
  v_tipo := v_l ->> 'tipo';
  -- a quem ele responde: a última que o sistema começou (ligado, enfileirada, dentro da validade)
  select * into m from public.agenda_equipe_mensagens x
   where x.payee_id = v_payee and x.tipo <> 'resposta' and x.modo = 'ligado' and x.estado = 'enfileirada'
     -- FASE 7b: (7b P3, §5.2 item 2) a pergunta dos dias da semana não é a mensagem a que ele responde no resto (ela tem o ramo dela)
     and x.tipo <> 'dias'
     -- FASE 7b: fim
     and x.enviar_em <= p_recebida_em and x.enviar_em >= p_recebida_em - cf.equipe_resposta_validade
   order by x.enviar_em desc, x.criada_em desc limit 1;
  -- o recibo das diárias mandado depois dela: o "ok" é do recibo (NOVO-agenda-17); a pergunta é sempre da agenda
  select max(a.enviado_ao_freelancer_em) into v_recibo
    from public.acertos_diarias a
   where a.favorecido_id = v_payee and a.status = 'fechado' and a.conferido_em is null
     and a.enviado_ao_freelancer_em > p_recebida_em - interval '7 days' and a.enviado_ao_freelancer_em <= p_recebida_em;
  if v_tipo <> 'pergunta' and v_recibo is not null and (m.id is null or v_recibo > m.enviar_em) then
    return jsonb_build_object('consumiu', false, 'motivo', 'recibo');
  end if;
  -- FASE 7b: (7b P3, §5.2 item 3; A1 = NOVO-agenda-52, A3 = NOVO-agenda-54) a resposta à pergunta dos dias da semana, antes da
  -- pergunta, do "não vou" e do "como foi":
  --   · os dias ou "nenhum" (em qualquer ordem: a frase com os dias é sobre a semana) gravam a semana presa — e o padrão de quem tem —
  --     pelo _agenda_equipe_dias_gravar (origem diarista; a exceção do dono no dia vence e volta em conflitos) e respondem
  --     "Anotei: …" (§6.1);
  --   · "igual" (ou "ok") com a pergunta por último: nada gravado, "Anotei: semana de 16/11 igual (de seg a sex). Obrigado!";
  --   · não entendi com a pergunta por último, e a leitura geral não é pergunta, presença nem turnos (o "não vou" junto de um dia da
  --     semana também: "segunda não posso" é sobre a semana, A3): na 1ª vez, "Não entendi os dias da semana de 16/11. …"; na 2ª, a
  --     pergunta equipe_resposta ao dono, e a mensagem fica respondida.
  -- Fora disso, o de antes (a mensagem a que ele responde é a última que o sistema começou, fora a pergunta da semana).
  if v_7b_mq.id is not null then
    v_7b_ult := v_7b_mq.enviar_em > coalesce(m.enviar_em, '-infinity'::timestamptz);
    v_7b_sem := to_char(v_7b_mq.dia, 'DD/MM');
    -- (correção da revisão da 7b, achado 8) a resposta só é da pergunta da semana quando ela é a última mensagem que o sistema
    -- mandou a ele (v_7b_ult), quando a frase fala da semana, ou quando é só a lista dos dias (o formato que a pergunta pede: "seg ter qui",
    -- "nenhum") e a leitura de sempre não a entende. Com a ficha, a confirmação ou o "como foi" mandados depois dela, "não posso", "ok,
    -- sexta tô lá", "sim, todos prontos" e "terminei todos" são a resposta a essas (o caminho de antes) e a pergunta da semana continua
    -- aberta: antes, viravam os dias da semana (e o padrão dele), e a falta de amanhã ficava sem replano.
    if not v_7b_ult and v_7b_vd ->> 'tipo' in ('dias', 'nenhum')
       and not (public._agenda_normal(p_body) ~ '\msemana\M')
       and not (v_tipo = 'nao_entendi'
                and btrim(regexp_replace(public._agenda_normal(p_body),
                                         '\m(segunda|terca|quarta|quinta|sexta|sabado|seg|ter|qua|qui|sex|sab|feira|nenhum|nenhuma|dia|dias|e|a|ate|so|somente|apenas|posso|consigo|vou|venho|todos|todo|toda|na|no|nos|de|do|da)s?\M',
                                         '', 'g')) = '') then
      v_7b_vd := v_7b_vd || jsonb_build_object('tipo', 'outra_mensagem');
    end if;
    -- (correção da revisão da 7b: fim)
    if v_7b_vd ->> 'tipo' in ('dias', 'nenhum') then
      v_7b_dias := array(select y::smallint from jsonb_array_elements_text(coalesce(v_7b_vd -> 'dias', '[]'::jsonb)) y);
      v_7b_sab := coalesce((v_7b_vd ->> 'sabado')::boolean, false);
      v_7b_g := public._agenda_equipe_dias_gravar(v_payee, v_7b_mq.dia, v_7b_dias, v_7b_sab, 'diarista', v_trecho, p_recebida_em,
                                                  v_7b_mq.id);
      v_7b_resp := case when cardinality(v_7b_dias) = 0 and not v_7b_sab
                        then format('Anotei: na semana de %s você não pode. Obrigado por avisar!', v_7b_sem)
                        else format('Anotei: na semana de %s você pode %s. Obrigado!', v_7b_sem,
                                    public._agenda_dias_curtos(v_7b_dias, v_7b_sab)) end;
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = v_7b_vd || jsonb_build_object('mudou', v_7b_g -> 'mudou', 'padrao_mudou', v_7b_g -> 'padrao_mudou',
                                                     'conflitos', coalesce(v_7b_g -> 'conflitos', '[]'::jsonb))
       where id = v_7b_mq.id;
      v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                             coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', v_7b_vd ->> 'tipo', 'mudou', v_7b_g -> 'mudou',
                                'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
    end if;
    if v_7b_vd ->> 'tipo' = 'igual' and v_7b_ult then
      v_7b_resp := format('Anotei: semana de %s igual (%s). Obrigado!', v_7b_sem,
                          public._agenda_dias_declarados(v_payee, v_7b_mq.dia) ->> 'texto');
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_7b_vd
       where id = v_7b_mq.id;
      v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                             coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'igual',
                                'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
    end if;
    if v_7b_vd ->> 'tipo' = 'nao_entendi' and v_7b_ult
       and (v_tipo not in ('pergunta', 'nao_vou', 'presenca', 'turnos')
            or (v_tipo = 'nao_vou'
                and public._agenda_normal(p_body) ~ '\m(segunda|terca|quarta|quinta|sexta|sabado|seg|ter|qua|qui|sex|sab)s?\M')) then
      if coalesce((v_7b_mq.leitura ->> 'nao_entendi')::int, 0) = 0 then
        v_7b_resp := format('Não entendi os dias da semana de %s. Mande só os dias, assim: seg ter qui (ou "nenhum").', v_7b_sem);
        update public.agenda_equipe_mensagens
           set leitura = coalesce(leitura, '{}'::jsonb)
                         || jsonb_build_object('nao_entendi', 1, 'trecho', v_trecho, 'recebida_em', p_recebida_em)
         where id = v_7b_mq.id;
        v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                               'dias:' || v_7b_mq.dia);
        return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'nao_entendi', 'vez', 1,
                                  'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
      end if;
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:dias', v_payee, v_7b_mq.dia), v_payee,
        null, v_7b_mq.dia,
        format('%s respondeu "%s" à pergunta dos dias da semana de %s, e eu não entendi. Diga os dias dele (ex.: %s vem seg e ter na semana de %s).',
               v_nome, public._agenda_corta(v_trecho, 120), v_7b_sem, v_nome, v_7b_sem),
        'ligado', p_recebida_em);
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = coalesce(v_7b_mq.leitura, '{}'::jsonb) || v_7b_vd || jsonb_build_object('nao_entendi', 2)
       where id = v_7b_mq.id;
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'nao_entendi', 'vez', 2, 'resposta', null);
    end if;
  end if;
  -- FASE 7b: fim

  -- ── pergunta: a ficha do publicado, sem valores (em sombra só registra) ──────────────────────────────
  if v_tipo = 'pergunta' then
    v_dia := case when v_l ->> 'dia' = 'amanha' then v_hoje + 1 else v_hoje end;
    v_f := public.agenda_equipe_ficha(v_payee, v_dia, v_hoje);
    v_r := public._agenda_equipe_registrar(v_payee, v_dia, 'resposta', v_f ->> 'texto_resposta', p_recebida_em, null,
                                           coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
    if v_r ? 'id' then
      update public.agenda_equipe_mensagens
         set leitura = v_l || jsonb_build_object('pergunta', v_trecho, 'recebida_em', p_recebida_em)
       where id = (v_r ->> 'id')::uuid;
    end if;
    if not coalesce((v_f ->> 'tem_plano')::boolean, false) and public.agenda_dia_util(v_dia) then
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:pergunta', v_payee, v_dia), v_payee,
        null, v_dia, format('O %s perguntou o que tem %s e ainda não tem plano para ele. Diga a ele o que fazer.', v_nome,
                            case when v_dia = v_hoje then 'hoje' else 'amanhã (' || public._dia_curto(v_dia) || ')' end),
        case when cf.modo_equipe = 'ligado' then 'ligado' else 'sombra' end, p_recebida_em);
    end if;
    return jsonb_build_object('consumiu', cf.modo_equipe = 'ligado', 'tipo', v_tipo,
                              'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_f ->> 'texto_resposta' end,
                              'envio', v_r ->> 'estado');
  end if;

  -- ── não vou (à ficha ou à confirmação; sem nada pendente: hoje antes do meio-dia, senão o próximo dia útil) ─
  -- (Revisão C1, item 3) também ao "como foi hoje?": aí o dia é o da ficha que ele levava (senão o próximo dia útil), e o
  -- "como foi" de hoje continua esperando a resposta de hoje (não vira a pergunta da diária de hoje)
  if v_tipo = 'nao_vou' and (m.id is null or m.tipo in ('ficha', 'confirmar', 'como_foi')) then
    -- (antes do fim da manhã, hoje; depois, o próximo dia útil)
    v_dia := case when m.tipo = 'como_foi' then coalesce(m.leva_ficha_de, public.agenda_somar_du(m.dia, 1))
                  else coalesce(m.dia, case when v_hora < cf.manha_fim then v_hoje else public.agenda_somar_du(v_hoje, 1) end) end;
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = v_payee and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                   order by 1);
    if cf.modo_equipe <> 'ligado' then
      -- em sombra nada muda: só o que faria
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
      values (clock_timestamp(), v_hoje, false, 'equipe', 'equipe', v_os[1], v_os, v_payee,
              jsonb_build_object('motivo', 'nao_vou', 'dia', v_dia, 'trecho', v_trecho),
              left(format('Em teste: o %s avisou que não vem %s; eu tiraria ele do plano desse dia.', v_nome,
                          public._agenda_dia_ref(v_dia, v_hoje)), 400));
      return jsonb_build_object('consumiu', false, 'tipo', v_tipo, 'modo', 'sombra');
    end if;
    perform set_config('agenda.hoje', v_hoje::text, true);
    if not exists (select 1 from public.agenda_disponibilidade d
                    where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'indisponivel'
                      and d.turno is null and d.periodo @> v_dia) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
      values (v_payee, daterange(v_dia, v_dia, '[]'), 'indisponivel', 'diarista', left('Avisou que não vem: ' || v_trecho, 200),
              left(v_trecho, 300), p_recebida_em)
      returning id into v_disp;
    end if;
    if cf.modo_proposta = 'ligado' and cardinality(v_os) > 0 then
      begin
        -- (C1, NOVO-agenda-27) a falta é evento real: o replano refaz os meios-dias que sobram da OS num bloco só, amanhã
        -- incluído (_agenda_violacoes lê agenda.replano_da_falta); o *desfaz* volta tudo
        perform set_config('agenda.replano_da_falta', 'on', true);
        v_rep := public.agenda_replanejar(v_os, 'equipe_faltou', 'vigia', v_hoje, p_recebida_em, null);
        perform set_config('agenda.replano_da_falta', '', true);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform set_config('agenda.replano_da_falta', '', true);
        perform public.log_app_error('db', 'agenda: replanejar depois do "não vou" da equipe falhou: ' || v_msg, 'agenda',
                                     'equipe:replanejar', 'error',
                                     jsonb_build_object('os', to_jsonb(v_os), 'sqlstate', v_estado, 'payee', v_payee));
      end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (clock_timestamp(), v_hoje, true, 'equipe', 'equipe', v_os[1], v_os, v_payee,
            jsonb_build_object('motivo', 'nao_vou', 'dia', v_dia, 'trecho', v_trecho, 'disponibilidade', v_disp,
                               'mensagem', m.id, 'replano_acoes', coalesce(v_rep -> 'acoes', '[]'::jsonb),
                               'acorde', v_dia <= public.agenda_somar_du(v_hoje, cf.congelamento_du)),
            left(format('O %s avisou que não vem %s.', v_nome, public._agenda_dia_da_equipe(v_dia, v_hoje))
                 || coalesce(' ' || nullif(v_rep ->> 'texto', ''), ''), 400))
    returning id into v_acao;
    -- (C1, item 3) o "como foi" de hoje não é respondido pelo "não vou" de amanhã: ele segue esperando a resposta de hoje
    if m.id is not null and m.tipo <> 'como_foi' then
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_l,
             acao_id = v_acao
       where id = m.id;
    end if;
    v_resp := format('Tá bom, aviso %s.', coalesce('o ' || (select public._agenda_nome_curto(p.name) from public.payees p
                                                              where p.id = public._agenda_dono(null)), 'o responsável'));
    v_r := public._agenda_equipe_registrar(v_payee, v_dia, 'resposta', v_resp, p_recebida_em, null,
                                           coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'acao_id', v_acao, 'dia', v_dia,
                              'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_resp end, 'envio', v_r ->> 'estado');
  end if;

  -- Daqui em diante só a resposta a uma mensagem que o sistema mandou.
  if m.id is null then
    return jsonb_build_object('consumiu', false, 'tipo', v_tipo);
  end if;

  -- ── à ficha ou à confirmação ────────────────────────────────────────────────────────────────────────
  if m.tipo in ('ficha', 'confirmar') then
    -- (Revisão C1, item 7) o "ok" com os turnos ditos diferentes do plano ("ok, só de manhã" com o dia todo no plano) não
    -- confirma o dia: vai ao dono, como o não entendido (com o plano no texto)
    v_plano := array(select distinct a.turno from public.agenda_alocacoes a
                      where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      order by 1);
    v_ditos := case when jsonb_typeof(v_l -> 'turnos') = 'array'
                    then array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1) end;
    v_div := v_tipo = 'turnos' and v_ditos is not null
             and not (v_ditos = v_plano or (v_ditos = array['meio'] and cardinality(v_plano) = 1));
    if not v_div
       and (v_tipo in ('ok', 'presenca') or (v_tipo = 'turnos' and coalesce((v_l ->> 'ok')::boolean, false))) then
      if not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'confirmada'
                        and d.turno is null and d.periodo @> m.dia) then
        insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
        values (v_payee, daterange(m.dia, m.dia, '[]'), 'confirmada', 'diarista',
                left(case m.tipo when 'ficha' then 'Confirmou a ficha: ' else 'Confirmou de manhã: ' end || v_trecho, 200),
                left(v_trecho, 300), p_recebida_em);
      end if;
    else
      -- não entendi (ou turnos sem ok): vai ao dono com o trecho, e nada muda (nem remaneja: não é silêncio)
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:%s', v_payee, m.dia, m.tipo), v_payee,
        null, m.dia, format('O %s respondeu "%s" à %s de %s', v_nome, public._agenda_corta(v_trecho, 120),
                            case m.tipo when 'ficha' then 'ficha' else 'confirmação' end, public._dia_curto(m.dia))
                     || case when v_div
                             then ', e o plano é ' || case when v_plano = array['manha', 'tarde'] then 'o dia todo'
                                                           when v_plano = array['manha'] then 'a manhã'
                                                           when v_plano = array['tarde'] then 'a tarde'
                                                           else 'sem nada para ele' end || '.'
                             else '.' end,
        'ligado', p_recebida_em);
    end if;
    update public.agenda_equipe_mensagens
       set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_l
     where id = m.id;
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'resposta', null);
  end if;

  -- ── ao "como foi hoje?" ─────────────────────────────────────────────────────────────────────────────
  v_plano := array(select distinct a.turno from public.agenda_alocacoes a
                    where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    order by 1);
  v_ent := true;
  if v_tipo = 'ok' or (v_tipo = 'turnos' and v_l -> 'turnos' = 'null'::jsonb and coalesce((v_l ->> 'ok')::boolean, false)) then
    -- "ok" = tudo como o previsto: os turnos do plano e terminou (salvo "ok, mas não terminei")
    v_ditos := v_plano;
    v_term := coalesce((v_l ->> 'terminou')::boolean, true);
  elsif v_tipo = 'turnos' and jsonb_typeof(v_l -> 'turnos') = 'array' then
    v_ditos := array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1);
    v_term := (v_l ->> 'terminou')::boolean;
  else
    -- não entendi, "terminei" sem o dia, "não vou"/presença fora de hora: a diária vira pergunta (crítica)
    v_ent := false;
    v_ditos := null;
    v_term := (v_l ->> 'terminou')::boolean;
  end if;
  -- FASE 7c: (7c P8, §16.5.3, §16.3.8; AG7-10b) com modo_tarefas ligado, as etapas do que devia ficar pronto hoje (de quem responde, sem
  -- resultado: _agenda_tarefas_da_pessoa) lidas sem IA (_agenda_ler_tarefas_da_resposta); com o "como foi" que não tem mais a lista de
  -- agora (_agenda_tarefas_texto_confere), os números não valem e só as palavras são lidas. A resposta só das etapas, sem turno nem OK,
  -- vale os turnos do plano para a diária só com tarefas_resposta_vale_dia = sempre, ou = tudo e "tudo"/"fiz tudo" — sem virar o tipo ok
  -- (o "fiz tudo" é sobre hoje: não confirma a ficha de amanhã que o "como foi" levava).
  if cf.modo_tarefas = 'ligado' then
    v_p8_dp := public._agenda_tarefas_da_pessoa(v_payee, m.dia, v_hoje);
    v_p8_lista := coalesce(v_p8_dp -> 'pergunta', '[]'::jsonb);
    if jsonb_array_length(v_p8_lista) > 0 then
      v_p8_lt := public._agenda_ler_tarefas_da_resposta(
                   case when public._agenda_tarefas_texto_confere(m.texto, v_p8_lista) then p_body
                        else regexp_replace(coalesce(p_body, ''), '[0-9]+', ' ', 'g') end,
                   v_p8_lista);
      if coalesce((v_p8_lt ->> 'entendeu')::boolean, false) and not v_ent and v_tipo in ('nao_entendi', 'turnos')
         and jsonb_typeof(v_l -> 'turnos') is distinct from 'array' and not coalesce((v_l ->> 'ok')::boolean, false)
         and (cf.tarefas_resposta_vale_dia = 'sempre'
              or (cf.tarefas_resposta_vale_dia = 'tudo' and coalesce((v_p8_lt ->> 'tudo')::boolean, false))) then
        v_ent := true;
        v_ditos := v_plano;
        v_term := coalesce((v_p8_lt ->> 'tudo')::boolean, false);
      end if;
    end if;
  end if;
  -- FASE 7c: fim
  update public.agenda_equipe_mensagens
     set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
         leitura = v_l || jsonb_build_object('entendeu', v_ent, 'turnos_lidos', to_jsonb(v_ditos), 'turnos_plano', to_jsonb(v_plano),
                                             'terminou', v_term)
   where id = m.id;
  -- FASE 7c: (7c P8, §16.5.3, §16.6.4) a leitura das etapas fica na mensagem (tarefas e a lista perguntada); a entendida grava as feitas
  -- e as pendentes (via equipe, por _agenda_tarefas_registrar: vale sobre a conferência); a que falou de falta sem dizer qual vira a
  -- pergunta equipe_resposta ao dono, e nada muda nas etapas.
  if v_p8_lt is not null then
    update public.agenda_equipe_mensagens
       set leitura = coalesce(leitura, '{}'::jsonb) || jsonb_build_object('tarefas', v_p8_lt, 'lista', v_p8_lista)
     where id = m.id;
    v_p8_its := coalesce(v_p8_dp -> 'itens', '[]'::jsonb);
    if coalesce((v_p8_lt ->> 'entendeu')::boolean, false) then
      perform public._agenda_tarefas_registrar(
        array(select (i ->> 'linha_id')::uuid from jsonb_array_elements(v_p8_its) i
               where (i ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'feitas') x)
                 and i ->> 'linha_id' is not null),
        'feita', 'equipe', v_trecho, m.id, p_recebida_em);
      perform public._agenda_tarefas_registrar(
        array(select (i ->> 'linha_id')::uuid from jsonb_array_elements(v_p8_its) i
               where (i ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'pendentes') x)
                 and i ->> 'linha_id' is not null),
        'pendente', 'equipe', v_trecho, m.id, p_recebida_em);
    elsif coalesce((v_p8_lt ->> 'falou_de_falta')::boolean, false) then
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:tarefas', v_payee, m.dia), v_payee,
        (v_p8_its -> 0 ->> 'os')::uuid, m.dia,
        format('O %s respondeu "%s" ao "como foi" do %s (%s), e não entendi o que faltou. Me diga qual (ex.: "no %s falta %s").',
               v_nome, public._agenda_corta(v_trecho, 120), v_p8_its -> 0 ->> 'cliente', public._dia_curto(m.dia),
               v_p8_its -> 0 ->> 'cliente',
               lower(left(v_p8_lista -> 0 ->> 'texto', 1)) || substr(v_p8_lista -> 0 ->> 'texto', 2)),
        'ligado', p_recebida_em);
    end if;
  end if;
  -- FASE 7c: fim
  if v_ent then
    v_conf := array(select x from unnest(v_ditos) x where x = any (v_plano) order by 1);
    perform set_config('agenda.hoje', v_hoje::text, true);
    -- FASE 7c: (7c P8, §16.5.3, §16.3.9) com a leitura das etapas entendida: o turno confirmado em que termina uma etapa pendente sai do
    -- cumprido e vai a parcial (o motivo da leitura, senão estimativa), por OS, logo depois do cumprido dos outros; as etapas que terminavam
    -- num turno que ele não confirmou ficam pendentes (via equipe).
    if v_p8_lt is not null then
      v_p8_conf := v_conf;
      v_p8_its := coalesce(v_p8_dp -> 'itens', '[]'::jsonb);
      if coalesce((v_p8_lt ->> 'entendeu')::boolean, false) then
        select coalesce(jsonb_object_agg(z.os, z.tus), '{}'::jsonb) into v_p8_parc
          from (select i ->> 'os' as os, jsonb_agg(distinct d.turno) as tus
                  from jsonb_array_elements(v_p8_its) i
                  join public.os_tarefas_dia d on d.id = (i ->> 'linha_id')::uuid
                 where (i ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'pendentes') x)
                   and d.turno = any (v_conf)
                 group by i ->> 'os') z;
        v_conf := array(select x from unnest(v_conf) x
                         where not exists (select 1 from jsonb_each(v_p8_parc) p, jsonb_array_elements_text(p.value) t where t = x)
                         order by 1);
      end if;
      perform public._agenda_tarefas_registrar(
        array(select d.id from jsonb_array_elements(coalesce(v_p8_dp -> 'pergunta', '[]'::jsonb)) q
                join jsonb_array_elements(v_p8_its) i on (i ->> 'n')::int = (q ->> 'n')::int
                join public.os_tarefas_dia d on d.id = (i ->> 'linha_id')::uuid
               where not (d.turno = any (v_p8_conf))
                 and not (v_ditos = array['meio'] and cardinality(v_plano) = 1)
                 and not (coalesce((v_p8_lt ->> 'entendeu')::boolean, false)
                          and (q ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'feitas') x))),
        'pendente', 'equipe', v_trecho, m.id, p_recebida_em);
    end if;
    -- FASE 7c: fim
    begin
      if cardinality(v_conf) > 0 then
        -- os turnos que ele confirmou viram resultado (via equipe), e a diária é decidida em seguida
        perform set_config('agenda.turnos_equipe', array_to_string(v_conf, ','), true);
        v_r := public.agenda_registrar_dia(null, m.dia, 'cumprido', null, null, array[v_payee], 'equipe', v_trecho, v_hoje,
                                           p_recebida_em, null);
        perform set_config('agenda.turnos_equipe', '', true);
      elsif v_ditos = '{}'::text[] then
        v_r := public.agenda_registrar_dia(null, m.dia, 'nao_cumprido', 'equipe', null, array[v_payee], 'equipe', v_trecho, v_hoje,
                                           p_recebida_em, null);
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      perform set_config('agenda.turnos_equipe', '', true);
      perform public.log_app_error('db', 'agenda: anotar o dia pela resposta da equipe falhou: ' || v_msg, 'agenda',
                                   'equipe:dia', 'error', jsonb_build_object('payee', v_payee, 'dia', m.dia, 'sqlstate', v_estado));
    end;
    -- FASE 7c: (7c P8, §16.5.3) o turno com etapa pendente: parcial, por OS (agenda_registrar_dia via equipe, só os turnos dela)
    for v_p8_os in select k from jsonb_object_keys(v_p8_parc) k order by 1 loop
      begin
        v_p8_tu := array(select x from jsonb_array_elements_text(v_p8_parc -> v_p8_os) x order by 1);
        perform set_config('agenda.turnos_equipe', array_to_string(v_p8_tu, ','), true);
        v_r := public.agenda_registrar_dia(null, m.dia, 'parcial', coalesce(v_p8_lt ->> 'motivo', 'estimativa'), v_p8_os::uuid,
                                           array[v_payee], 'equipe', v_trecho, v_hoje, p_recebida_em, null);
        perform set_config('agenda.turnos_equipe', '', true);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform set_config('agenda.turnos_equipe', '', true);
        perform public.log_app_error('db', 'agenda: anotar o parcial pelas etapas da equipe falhou: ' || v_msg, 'agenda',
                                     'tarefas:parcial', 'error',
                                     jsonb_build_object('payee', v_payee, 'dia', m.dia, 'os', v_p8_os, 'sqlstate', v_estado));
      end;
    end loop;
    -- FASE 7c: fim
    -- o "ok" ao "como foi" que levava a ficha de amanhã confirma amanhã também — (C1, item 3) salvo se ele já disse que
    -- não vem amanhã (o "ok" depois do "amanhã não vou" é sobre hoje)
    if v_tipo = 'ok' and m.leva_ficha_de is not null
       and not exists (select 1 from public.agenda_disponibilidade d
                        where d.payee_id = v_payee and d.substituida_em is null and d.situacao in ('confirmada', 'indisponivel')
                          and d.turno is null and d.periodo @> m.leva_ficha_de) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
      values (v_payee, daterange(m.leva_ficha_de, m.leva_ficha_de, '[]'), 'confirmada', 'diarista',
              left('Confirmou a ficha junto do "como foi": ' || v_trecho, 200), left(v_trecho, 300), p_recebida_em);
    end if;
  end if;
  -- a diária do dia (idempotente: o agenda_registrar_dia já a chamou quando anotou)
  begin
    v_r := public._agenda_diaria_do_dia(v_payee, m.dia, 'equipe', v_hoje, p_recebida_em);
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    perform public.log_app_error('db', 'agenda: a diária pela resposta da equipe falhou: ' || v_msg, 'agenda', 'equipe:diaria',
                                 'error', jsonb_build_object('payee', v_payee, 'dia', m.dia, 'sqlstate', v_estado));
  end;
  return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'entendeu', v_ent, 'resposta', null, 'diaria', v_r ->> 'status');
end;
$function$;

comment on function public.agenda_resposta_da_equipe(text, text, text, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a mensagem do técnico (número que não é login de admin), chamada pelo whatsapp-webhook antes da confirmação do cliente e da conferência do recibo. modo_equipe desligado, telefone de ninguém da equipe (ou de dois) = {consumiu: false}. A mesma mensagem (p_message_id) de novo = nada muda. Lida por _agenda_ler_resposta_da_equipe. Decide a última mensagem que o sistema mandou (ligado, enfileirada, dentro de equipe_resposta_validade); o recibo de diárias mandado depois dela fica com o "ok" (NOVO-agenda-17: consumiu false). pergunta → a ficha do publicado (agenda_equipe_ficha.texto_resposta) como resposta enfileirada (sem plano: a pergunta equipe_resposta ao dono); em sombra só registra (consumiu false). nao_vou → indisponível no dia (agenda_disponibilidade origem diarista), replano (modo_proposta ligado, origem vigia), ação equipe com o acorde para a rotina e "Tá bom, aviso o Gustavo."; em sombra só a ação executada = false. ok/presença à ficha ou à confirmação → confirmada, sem resposta; não entendido → equipe_resposta ao dono, sem remanejo. Ao "como foi hoje?": ok = os turnos do plano e terminou; os turnos ditos viram resultado (agenda_registrar_dia via equipe, só os turnos confirmados) e a diária (_agenda_diaria_do_dia); não entendido = a pergunta crítica da diária. Sem pendente (ok, turnos, presença, não entendi) = consumiu false. {consumiu, tipo, resposta, acao_id}. Só service_role. FASE 7b (P3, §5.2; A1 = NOVO-agenda-52, A2, A3 = NOVO-agenda-54): com modo_dias ligado, a resposta à pergunta dos dias da semana (a mensagem dias ligada, enfileirada, mandada antes e com o prazo da semana por vir) é lida por _agenda_ler_dias_da_equipe ANTES da pergunta, do "não vou" e do "como foi": os dias ou "nenhum" (em qualquer ordem) gravam a semana presa e o padrão de quem tem (_agenda_equipe_dias_gravar, origem diarista; a exceção do dono no dia vence e volta em leitura.conflitos), a mensagem fica respondida e sai "Anotei: na semana de 16/11 você pode seg, ter e qui. Obrigado!" / "… você não pode. Obrigado por avisar!"; "igual"/"ok" com a pergunta por último: nada gravado, "Anotei: semana de 16/11 igual (de seg a sex). Obrigado!"; não entendido com a pergunta por último (e a leitura geral não é pergunta, presença nem turnos; o "não vou" junto de um dia da semana também — "segunda não posso" nunca vira o "não vou" da ficha): 1ª vez "Não entendi os dias da semana de 16/11. Mande só os dias, assim: seg ter qui (ou "nenhum")." (chave agenda-equipe:resposta:<pessoa>:dias:<segunda>), 2ª vez a pergunta equipe_resposta ao dono e a mensagem respondida. {consumiu: true, tipo: dias, leitura, …}. A "última que o sistema começou" do resto não é mais a pergunta da semana. Fora disso, o de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achado 8): com modo_dias ligado, a pergunta da semana aberta só leva a resposta (os dias ou "nenhum") quando é a última mensagem mandada a ele, quando a frase fala da semana ou quando é só a lista dos dias e a leitura de sempre não a entende; com a ficha, a confirmação ou o "como foi" mandados depois, "não posso", "ok, sexta tô lá", "sim, todos prontos" e "terminei todos" seguem o caminho de antes (o "não vou", a confirmação, os turnos) e a pergunta da semana continua aberta. FASE 7c (P8, §16.5.3, §16.3.8; AG7-10b): com modo_tarefas ligado, no "como foi" a lista do que devia ficar pronto (de quem responde, sem resultado) é lida por _agenda_ler_tarefas_da_resposta (com o texto que não tem mais a lista de agora, só as palavras) e gravada na mensagem (tarefas, lista); a entendida grava as feitas e as pendentes via equipe (_agenda_tarefas_registrar), o turno confirmado em que termina uma pendente sai do cumprido e vai a parcial (o motivo da leitura, senão estimativa), por OS, e as etapas de turno não confirmado ficam pendentes; a que falou de falta sem dizer qual vira a pergunta equipe_resposta ao dono ("O Alex respondeu "faltou umas coisas" ao "como foi" do Lenine (qua 04/11), e não entendi o que faltou. Me diga qual (…)."); a resposta só das etapas vale os turnos do plano para a diária com tarefas_resposta_vale_dia sempre, ou tudo e "tudo" (sem virar o tipo ok). Desligado ou em teste: a de antes, byte a byte.';

-- _agenda_linhas_do_fechamento (de 20261102100400_agenda_fase7c_rodada.sql)
create or replace function public._agenda_linhas_do_fechamento(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_max   constant int := 480;   -- estrutural: uma linha da agenda no fechamento
  -- FASE 3: o fim do texto da conferência da vigia (é o que a linha dia troca quando tem o que contar da equipe)
  c_cauda constant text := ' Foi isso? Responda *dia feito* ou conte o que mudou.';
  v_ini   date;
  v_am1   date;
  v_am2   date;
  v_out   jsonb := '[]'::jsonb;
  q       record;
  g       jsonb;
  v_m     jsonb;
  v_ms    jsonb;
  v_conf  record;
  v_txts  text[];
  v_ids   jsonb;
  v_txt   text;
  v_mod   text;
  v_n     int;
  k       int;
  m       text;
  -- FASE 3
  v_eq    jsonb;
  v_base  text;
  v_dia   text;
  v_som   text;
  v_extra text;
  v_cauda text;
  v_pend  jsonb;
  v_tec   text;
  v_cob   text;
  v_ppc   jsonb;
  v_com   jsonb;
  -- FASE 7: (7a P7) a linha do gestor em teste e a das compras da semana
  v_f7_txt   text;
  v_f7_cmp   jsonb;
  v_f7_min   date;
  v_f7_urg   boolean;
  v_f7_perda int;
  -- FASE 7: fim
  -- FASE 7: (7a correção, achados 15 e 18) a linha das perguntas do gestor
  c_max_perg  constant int := 600;   -- estrutural: até 640 na coleta, como a do cliente
  v_f77_ids   jsonb;
  v_f77_txt   text;
  v_f77_prazo boolean;
  v_f77_segs  text[];
  v_f77_grupo text;
  v_f77_itens text[];
  v_f77_rest  int;
  v_f77_nl    text;
  v_f77_item  text;
  v_f77_ns    text[];
  v_f77_ni    text[];
  v_f77_l     text;
  v_f77_q     record;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, R4.2(d)) a linha (n) da equipe
  v_7b_on     boolean;
  v_7b_ids    jsonb;
  v_7b_txt    text;
  v_7b_itens  text[];
  v_7b_curtos text[];
  v_7b_rest   int;
  v_7b_perde  boolean;
  v_7b_lig    boolean;
  v_7b_item   text;
  v_7b_curto  text;
  v_7b_l      text;
  v_7b_q      record;
  -- (correção 3) o prazo de quem vence, na forma curta
  v_c3_ate    timestamptz;
  -- (correção 3: fim)
  -- FASE 7b: fim
  -- FASE 7c: (7c P5, R5.4 item 4) a linha (n) com as perguntas de quem faz o quê
  v_7c_on    boolean;
  v_7c_7b    boolean;
  v_7c_q     record;
  v_7c_eq    boolean;
  v_7c_marc  text;
  v_7c_exig  text;
  v_7c_ate   timestamptz;
  -- FASE 7c: fim
  -- FASE 7c: (7c P8, R5.4 item 4, R5.2-2(b)) as perguntas das etapas na linha (n) e a linha (o) das etapas
  v_p8_on     boolean;
  v_p8_q      record;
  v_p8_quem   boolean;
  v_p8_pess   record;
  v_p8_h      jsonb;
  v_p8_a      jsonb;
  v_p8_hi     jsonb;
  v_p8_ai     jsonb;
  v_p8_nomes  text[] := '{}';
  v_p8_nfone  int;
  v_p8_nrot   int;
  v_p8_hoje   jsonb := '[]'::jsonb;
  v_p8_amanha jsonb := '[]'::jsonb;
  v_p8_txt    text;
  v_p8_curto  text;
  v_p8_alta   boolean;
  v_p8_k      int;
  v_p8_g      record;
  v_p8_parte  text[];
  v_p8_dia    text;
  -- FASE 7c: fim
begin
  if p_hoje is null then
    raise exception 'agenda: sem o dia de hoje' using errcode = '22004';
  end if;
  if cf.modo_proposta = 'desligado' and cf.modo_vigia = 'desligado' then
    return '[]'::jsonb;
  end if;
  v_ini := p_hoje - 6;
  v_am1 := public.agenda_somar_du(p_hoje, 1);
  v_am2 := public.agenda_somar_du(p_hoje, 2);

  -- (a) as decisões críticas abertas
  -- FASE 3: menos a da diária, que tem a linha dela (b2)
  for q in select x.* from public.agenda_perguntas x where x.critica and x.estado = 'aberta' and x.tipo <> 'diaria'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'decisao',
      'texto', 'Agenda, preciso de você. ' || q.texto || ' Me responda aqui.',
      'perda', case when q.perda_em is not null and q.perda_em <= v_am1 then 100
                    when q.perda_em is not null and q.perda_em <= v_am2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 3 (a2): a diária que diverge do plano (crítica): as opções, a recomendação e as palavras que respondem.
  -- A perda: o banco não sabe quando o acerto fecha (o dono fecha quando quer); com 2 dias úteis sem resposta, 80.
  for q in select x.* from public.agenda_perguntas x where x.tipo = 'diaria' and x.estado = 'aberta'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'diaria',
      'texto', 'Diária, preciso de você: ' || public._agenda_texto_da_diaria(q.id),
      'perda', case when public.agenda_du_entre(coalesce(q.dia, q.perda_em, p_hoje), p_hoje) >= 2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_diaria = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- (b) o que mudou sozinho (de verdade e na sombra), ainda não contado
  v_m := public._agenda_mudancas(v_ini, p_hoje, true, true, null);
  v_ms := public._agenda_mudancas(v_ini, p_hoje, false, true, null);

  -- (c) a semana publicada
  for g in select x from jsonb_array_elements(v_m) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', (g ->> 'desfazivel')::boolean, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids',
      'modo', case when cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;
  for g in select x from jsonb_array_elements(v_ms) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', false, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids', 'modo', 'sombra');
  end loop;

  -- (d) a conferência de hoje, com o que mudou sozinho; sem ela, o que mudou numa linha só
  select x.* into v_conf from public.agenda_perguntas x
   where x.tipo = 'conferencia' and x.estado = 'aberta' and x.dia = p_hoje
   order by (x.modo = 'ligado') desc, x.criada_em desc, x.id desc limit 1;
  -- FASE 3: o que a equipe confirmou, a diária que a agenda lançou, quem falta confirmar e o último dia da OS
  v_eq := public._agenda_dia_da_equipe(p_hoje);
  v_pend := v_eq -> 'pendentes';
  v_extra := nullif(array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'lig') x
                                          union all select x from jsonb_array_elements_text(v_eq -> 'ultimo') x), ' '), '');
  for m in select unnest(array['ligado', 'sombra']) loop
    v_txts := array(select public._agenda_mudanca_texto(x, false)
                      from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o)
                     where x ->> 'tipo' = 'acao' order by o);
    v_ids := coalesce((select jsonb_agg(y order by o, o2)
                         from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o),
                              jsonb_array_elements(x -> 'acao_ids') with ordinality u(y, o2)
                        where x ->> 'tipo' = 'acao'), '[]'::jsonb);
    v_mod := case when m = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end;
    if v_conf.id is not null and v_conf.modo = m then
      -- FASE 3: o texto do dia com a equipe. Sem nada a contar, é o da conferência, byte a byte.
      v_dia := v_conf.texto;
      if v_extra is not null or jsonb_array_length(v_pend) > 0 then
        v_base := case when right(v_conf.texto, char_length(c_cauda)) = c_cauda
                       then left(v_conf.texto, char_length(v_conf.texto) - char_length(c_cauda)) else v_conf.texto end;
        v_cauda := case
          when jsonb_array_length(v_pend) = 1
            then format(' Foi isso para o %s? *dia feito* lança a %s dele, ou conte o que mudou.', v_pend -> 0 ->> 'nome',
                        case when (v_pend -> 0 ->> 'meios')::int = 1 then 'meia diária' else 'diária' end)
          when jsonb_array_length(v_pend) > 1
            then format(' Foi isso para %s? *dia feito* lança as diárias deles, ou conte o que mudou.',
                        public._agenda_lista(array(select 'o ' || (e ->> 'nome') from jsonb_array_elements(v_pend) with ordinality t(e, o)
                                                    order by o), null))
          when (v_eq ->> 'aguardando')::int > 0 and cf.modo_diaria = 'ligado' then ' Foi isso? *dia feito* lança agora.'
          else c_cauda end;
        v_dia := v_base || coalesce(' ' || v_extra, '') || v_cauda;
      end if;
      v_ids := v_ids || (v_eq -> 'ids');
      for k in reverse cardinality(v_txts) .. 0 loop
        v_txt := v_dia
                 || case when k > 0 then ' Mudei sozinho: ' || array_to_string(v_txts[1:k], ' ')
                                         || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end
                         when cardinality(v_txts) > 0 then format(' Mudei sozinho %s: *o que mudou* mostra.',
                                                                   public._agenda_plural(cardinality(v_txts), 'coisa', 'coisas'))
                         else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', v_txt, 'perda', 70, 'pergunta_id', v_conf.id, 'acao_ids', v_ids,
        'modo', case when v_conf.modo = 'ligado' and cf.modo_vigia = 'ligado' and v_mod = 'ligado' then 'ligado' else 'sombra' end);
      -- FASE 3: o que a sombra da equipe e da diária diria, só no detalhe
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_som := v_dia || ' ' || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' ');
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_som, c_max), 'perda', 70,
                                             'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    elsif cardinality(v_txts) > 0 then
      for k in reverse cardinality(v_txts) .. 1 loop
        v_txt := 'Agenda, mudei sozinho. ' || array_to_string(v_txts[1:k], ' ')
                 || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'mudancas', 'texto', v_txt, 'perda', 40, 'pergunta_id', null, 'acao_ids', v_ids,
                                           'modo', v_mod);
    end if;
  end loop;
  -- a conferência na sombra sem nada a contar junto, ou de um modo sem mudança (o laço acima já cobriu quem teve)
  -- (nada a fazer: o laço passa pelos dois modos)

  -- FASE 3 (d1): sem a conferência aberta (todos confirmaram), o dia com o que a equipe e a diária contam numa linha
  -- própria: a diária que a agenda lançou ("*diária Roberto meia* corrige") e o último dia da OS.
  if v_conf.id is null and (v_extra is not null or jsonb_array_length(v_eq -> 'som') > 0) then
    v_base := public._agenda_texto_do_dia(p_hoje);
    if v_base is not null then
      v_cauda := case when jsonb_array_length(v_eq -> 'lancadas') > 0
                      then format(' *diária %s %s* corrige.', v_eq -> 'lancadas' -> 0 ->> 'nome',
                                  case when (v_eq -> 'lancadas' -> 0 ->> 'fracao')::numeric = 1 then 'meia' else 'inteira' end)
                      else '' end;
      if v_extra is not null then
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_base || ' ' || v_extra || v_cauda, c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', v_eq -> 'ids',
          'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
      end if;
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_out := v_out || jsonb_build_object('tipo', 'dia',
          'texto', public._agenda_corta(v_base || coalesce(' ' || v_extra, '') || ' '
                                        || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' '), c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    end if;
  end if;

  -- FASE 3 (d2): o que o gestor concluiu pela palavra do técnico (o técnico disse que terminou e era o último dia do
  -- plano), ainda não contado: a cobrança que a conclusão disse e o *desfaz* pelo número (a OS saiu da carteira).
  for q in select x.* from public.agenda_acoes x
            where x.tipo = 'concluir' and x.origem = 'equipe' and x.contada_em is null and x.desfeita_em is null
              and x.dia between v_ini and p_hoje
            order by x.criada_em, x.id loop
    v_tec := (select public._agenda_nome_curto(py.name) from public.agenda_equipe_mensagens em
                join public.payees py on py.id = em.payee_id where em.acao_id = q.id
               order by em.resposta_em desc nulls last limit 1);
    if q.executada then
      -- revisão da Fase 3 (item 5): o "vence hoje" de outro dia pelo ajudante único
      v_cob := public._agenda_vence_no_dia(regexp_replace(q.texto, '^[^—]* — saída [^.]*\.\s*', ''), q.dia, p_hoje);
      v_txt := format('Concluí o %s%s: o %s disse que terminou e era o último dia do plano.%s *desfaz %s* reabre.',
                      public._agenda_rotulo_da_os(q.service_order_id),
                      case when q.dia <> p_hoje then ' ' || public._dia_curto(q.dia) else '' end,
                      coalesce(v_tec, 'técnico'), coalesce(' ' || nullif(v_cob, q.texto), ''),
                      (select so.service_order_number from public.service_orders so where so.id = q.service_order_id));
    else
      v_txt := q.texto;
    end if;
    v_out := v_out || jsonb_build_object('tipo', 'conclusao', 'texto', public._agenda_corta(v_txt, c_max), 'perda', 45,
      'pergunta_id', null, 'acao_ids', jsonb_build_array(q.id),
      'modo', case when q.executada and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 7: (7a correção, achados 15 e 18; no lugar da linha (l) do 7a P11) (m) as perguntas do gestor que esperam o dono numa
  -- linha só: a ficha_estimativa de hoje (a ficha das 19:30 de um dia pela estimativa, que perde hoje), a situacao, a estimativa e
  -- o reestimar. Antes, cada uma disputava sozinha a vaga da pergunta de fato (e), de perda 30, e nenhuma chegava ao dono: o prazo
  -- só vale com a pergunta vista, e o gestor não marcava (Nelson, Flávio, Giancarlo e MP fora a semana inteira); a da ficha perdia
  -- para a mensagem ao cliente da véspera, e a ficha do 1º dia ficava segurada. A 1ª (a ficha; depois a de prazo mais perto) vai
  -- com o texto inteiro; as outras curtas, agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4
  -- dias; Flávio (OS-00104) 3,5 dias."; sem prazo: "Espero você: Giancarlo (OS-00130)."), até c_max_perg; o resto fica para
  -- *agenda gestor*. O fechamento que sai conta como mostradas todas as que a linha leva (pergunta_ids). Perda 75 com alguma de
  -- prazo (ela perde no prazo), 30 sem; modo = o da vigia.
  for m in select unnest(array['ligado', 'sombra']) loop
    v_f77_ids := '[]'::jsonb;
    v_f77_txt := null;
    v_f77_prazo := false;
    v_f77_segs := '{}';
    v_f77_grupo := null;
    v_f77_itens := '{}';
    v_f77_rest := 0;
    for v_f77_q in
      select x.id, x.texto, x.veto_ate, x.service_order_id, x.tipo,
             case when x.veto_ate is null then null
                  else public._dia_curto((x.veto_ate at time zone 'America/Sao_Paulo')::date) || ' '
                       || to_char(x.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI') end as ate,
             (select (o -> 'efeito' ->> 'dias')::numeric from jsonb_array_elements(coalesce(x.opcoes, '[]'::jsonb)) o
               where (o ->> 'n')::int = x.opcao_padrao limit 1) as dias_padrao
        from public.agenda_perguntas x
       where x.estado = 'aberta' and x.modo = m and not x.critica and x.opcao_escolhida is null
         and ((x.tipo = 'ficha_estimativa' and x.veto_ate is not null
               and (x.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
              or (x.tipo in ('situacao', 'estimativa', 'reestimar')
                  and (x.veto_ate is null or (x.veto_ate at time zone 'America/Sao_Paulo')::date >= p_hoje)))
         and x.mostrada_vezes < cf.perguntas_vezes_max
         and not exists (select 1 from public.agenda_dono_avisos v
                          where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       order by x.tipo = 'ficha_estimativa' desc, x.veto_ate nulls last, x.criada_em, x.id
    loop
      if v_f77_txt is null then
        v_f77_txt := 'Agenda: ' || v_f77_q.texto;
        v_f77_ids := jsonb_build_array(v_f77_q.id);
        v_f77_prazo := v_f77_q.veto_ate is not null;
        continue;
      end if;
      if v_f77_rest > 0 then
        v_f77_rest := v_f77_rest + 1;
        continue;
      end if;
      -- (7a correção 2) sem prazo, o porquê junto: acima do teto de diárias o gestor não marca sozinho
      v_f77_nl := case when v_f77_q.ate is null then 'Espero você (não marco sozinho): ' else format('Também, sem resposta até %s: ', v_f77_q.ate) end;
      v_f77_item := public._agenda_rotulo_da_os(v_f77_q.service_order_id)
                    || case when v_f77_q.dias_padrao is not null then ' ' || public._agenda_dias(v_f77_q.dias_padrao) else '' end;
      if v_f77_nl is distinct from v_f77_grupo then
        v_f77_ns := v_f77_segs || case when v_f77_grupo is not null then array[v_f77_grupo || array_to_string(v_f77_itens, '; ') || '.']
                                       else '{}'::text[] end;
        v_f77_ni := array[v_f77_item];
      else
        v_f77_ns := v_f77_segs;
        v_f77_ni := v_f77_itens || v_f77_item;
      end if;
      v_f77_l := v_f77_txt || ' ' || array_to_string(v_f77_ns || (v_f77_nl || array_to_string(v_f77_ni, '; ') || '.'), ' ');
      -- cabe com o "(e mais N em *agenda gestor*)" que pode vir depois
      if char_length(v_f77_l) > c_max_perg - 32 then
        v_f77_rest := 1;
        continue;
      end if;
      v_f77_segs := v_f77_ns;
      v_f77_grupo := v_f77_nl;
      v_f77_itens := v_f77_ni;
      v_f77_ids := v_f77_ids || to_jsonb(v_f77_q.id);
      v_f77_prazo := v_f77_prazo or v_f77_q.veto_ate is not null;
    end loop;
    continue when v_f77_txt is null;
    v_f77_l := v_f77_txt
               || case when v_f77_grupo is not null
                       then ' ' || array_to_string(v_f77_segs || (v_f77_grupo || array_to_string(v_f77_itens, '; ') || '.'), ' ')
                       else '' end
               || case when v_f77_rest > 0 then format(' (e mais %s em *agenda gestor*)', v_f77_rest) else '' end;
    -- (7a correção 2, os achados 15/18 de novo) perda 76 com alguma de prazo: entre as linhas que perdem hoje ela ganha o desempate
    -- (antes, 75 com a mensagem ao cliente, ela perdia pelo tipo — "cliente" < "pergunta" — e saía primeiro no corte de 1.000)
    -- (7a correção 2) o objeto da linha entre parênteses: a forma curta (abaixo) entra nele, não como outro item da lista
    v_out := v_out || (jsonb_build_object('tipo', 'pergunta', 'texto', v_f77_l, 'perda', case when v_f77_prazo then 76 else 30 end,
      'pergunta_id', v_f77_ids ->> 0, 'pergunta_ids', v_f77_ids, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end)
      -- (7a correção 2, o corte de 1.000 do fechamento) a mesma linha na forma curta (texto_curto), com as MESMAS perguntas: a
      -- ficha sem as opções ("… pela minha estimativa. Para segurar, me diga.") e cada uma pelo prazo e pelo que o gestor faz sem
      -- resposta ("Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; …"). O Secretário cheio (3 que ficaram, ~900
      -- caracteres) usa esta antes de tirar a linha — a inteira (~400) não cabia e as perguntas nunca eram vistas.
      || coalesce((select jsonb_build_object('texto_curto', k.t) from (select
           'Agenda: ' || concat_ws(' ',
             (select split_part(pc.texto, ' 1) Mande', 1) || ' Para segurar, me diga.' from public.agenda_perguntas pc
               where pc.id = (v_f77_ids ->> 0)::uuid and pc.tipo = 'ficha_estimativa'),
             (select string_agg(g.grupo || g.itens || '.', ' ' order by g.ord)
                from (select case when y.ate is null then 'Espero você (não marco sozinho): '
                                  else format('Sem resposta até %s, conto: ', y.ate) end as grupo,
                             string_agg(y.item, '; ' order by y.o) as itens, min(y.o) as ord
                        from (select t.o,
                                     case when pc.veto_ate is null then null
                                          else public._dia_curto((pc.veto_ate at time zone 'America/Sao_Paulo')::date) || ' '
                                               || to_char(pc.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI') end as ate,
                                     public._agenda_rotulo_da_os(pc.service_order_id)
                                     || coalesce(' ' || public._agenda_dias((select (op -> 'efeito' ->> 'dias')::numeric
                                                                               from jsonb_array_elements(coalesce(pc.opcoes, '[]'::jsonb)) op
                                                                              where (op ->> 'n')::int = pc.opcao_padrao limit 1)), '') as item
                                from jsonb_array_elements_text(v_f77_ids) with ordinality t(id, o)
                                join public.agenda_perguntas pc on pc.id = t.id::uuid
                               where pc.tipo <> 'ficha_estimativa') y
                       group by y.ate) g)) as t) k
         where char_length(k.t) < char_length(v_f77_l)), '{}'::jsonb));
  end loop;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, R4.2(d)) (n) a equipe: as perguntas abertas da equipe — a chamada (equipe_cadastro:chamada), a dos dias do
  -- dono (dias_semana), o telefone e o contato — numa linha só, nesta ordem e depois a mais antiga. Pela pergunta de fato (e), de perda
  -- 30, elas nunca entravam nas vagas (as de fornecedor estão abertas e nunca vistas desde 28/10): a chamada nunca seria vista nem
  -- venceria, e a pergunta da semana ficaria esperando por ela. A 1ª vai com o texto inteiro; as outras, curtas, até c_max_perg; o
  -- resto "(e mais N em *agenda equipe*)". pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas;
  -- a chamada vista ganha o prazo na rodada da semana). Perda 75 enquanto alguma nunca foi mostrada (o prazo só começa depois de vista)
  -- ou perde hoje (o veto_ate ou o perda_em de hoje): vaga própria entre as que perdem hoje; senão 30. Modo ligado só com a pergunta
  -- em ligado e o modo dela (o de _agenda_modo_da_pergunta: modo_dias; modo_cadastro fora de desligado, senão o do gestor) ligado.
  -- texto_curto = as mesmas perguntas só pelo nome. Só com modo_dias ou modo_cadastro fora de desligado (senão, o de antes); a (e)
  -- não as repete.
  v_7b_on := cf.modo_dias <> 'desligado' or cf.modo_cadastro <> 'desligado';
  -- (7c P5, R5.4 item 4, R5.10-8) o portão da linha separado por etapa: o bloco roda com a 7b (modo_dias ou modo_cadastro) OU com
  -- a 7c (modo_habilidade_propor ou modo_habilidade) fora de desligado; dentro dele, as perguntas da 7b só entram com o portão da 7b
  -- (v_7c_7b) e as de quem faz o quê só com o da 7c (v_7c_on). v_7b_on volta a ser só o da 7b logo depois do bloco: a pergunta de fato
  -- (e) exclui só os tipos que a (n) levou (sem isso, com a 7b desligada e a 7c em teste, a chamada da 7a sairia da (e), perda 30,
  -- para a (n), perda 75, e o texto do dono mudaria).
  v_7c_on := cf.modo_habilidade_propor <> 'desligado' or cf.modo_habilidade <> 'desligado';
  v_7c_7b := v_7b_on;
  v_7b_on := v_7b_on or v_7c_on;
  -- (7c: fim)
  -- (7c P8, R5.4 item 4) e com as etapas (modo_tarefas) fora de desligado: as perguntas das etapas (tarefa) só com o portão delas
  v_p8_on := cf.modo_tarefas <> 'desligado';
  v_7b_on := v_7b_on or v_p8_on;
  -- (7c: fim)
  if v_7b_on then
    for m in select unnest(array['ligado', 'sombra']) loop
      v_7b_ids := '[]'::jsonb;
      v_7b_txt := null;
      v_7b_itens := '{}';
      v_7b_curtos := '{}';
      v_7b_rest := 0;
      v_7b_perde := false;
      v_7b_lig := true;
      for v_7b_q in
        select x.id, x.tipo, x.chave, x.texto, x.dia, x.mostrada_vezes, x.veto_ate, x.perda_em,
               coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = x.payee_id), '') as nome,
               case when x.tipo = 'dias_semana' then cf.modo_dias
                    when cf.modo_cadastro <> 'desligado' then cf.modo_cadastro
                    else public._agenda_gestor_modo('marcar') end as modo_agora
          from public.agenda_perguntas x
         where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo in ('equipe_cadastro', 'dias_semana')
           and x.mostrada_vezes < cf.perguntas_vezes_max
           and not exists (select 1 from public.agenda_dono_avisos v
                            where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
         order by case when x.chave like 'equipe_cadastro:chamada:%' then 1 when x.tipo = 'dias_semana' then 2
                       when x.chave like 'equipe_cadastro:telefone:%' then 3 else 4 end, x.criada_em, x.id
      loop
        -- (7c P5) as perguntas da equipe da 7b só com o portão da 7b (o bloco pode estar rodando só pela 7c)
        continue when not v_7c_7b;
        -- (7c: fim)
        v_7b_curto := case
          when v_7b_q.chave like 'equipe_cadastro:chamada:%' then 'a equipe da agenda está certa?'
          when v_7b_q.tipo = 'dias_semana' then format('os dias da semana de %s', to_char(v_7b_q.dia, 'DD/MM'))
          when v_7b_q.chave like 'equipe_cadastro:telefone:%' then format('o telefone do %s', v_7b_q.nome)
          else format('%s na rotina da equipe?', v_7b_q.nome) end;
        if v_7b_txt is null then
          v_7b_txt := 'Agenda: ' || v_7b_q.texto;
        else
          if v_7b_rest > 0 then
            v_7b_rest := v_7b_rest + 1;
            continue;
          end if;
          v_7b_item := case
            when v_7b_q.chave like 'equipe_cadastro:telefone:%'
              then format('Também: o telefone do %s (sem ele não mando a ficha).', v_7b_q.nome)
            when v_7b_q.chave like 'equipe_cadastro:contato:%'
              then format('Também: %s tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*.', v_7b_q.nome)
            when v_7b_q.tipo = 'dias_semana'
              then format('Também: os dias da semana de %s (responda em *agenda pendências*).', to_char(v_7b_q.dia, 'DD/MM'))
            else 'Também: a chamada da equipe (responda em *agenda pendências*).' end;
          if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
            v_7b_rest := 1;
            continue;
          end if;
          v_7b_itens := v_7b_itens || v_7b_item;
        end if;
        v_7b_ids := v_7b_ids || to_jsonb(v_7b_q.id);
        -- (correção da revisão da 7b, achado 17) a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda
        -- pendências*)" não contam como mostradas: o dono não leu a pergunta (a dos dias, com a sugestão de quem chamar, contava como vista
        -- e vencia na quinta seguinte sem ele a ter lido). Elas ficam com mostrada_vezes 0 (a linha segue com perda 75) e saem inteiras no
        -- fechamento em que vierem primeiro. O telefone e o contato vão com a pergunta toda na forma curta e contam.
        if jsonb_array_length(v_7b_ids) > 1 and (v_7b_q.tipo = 'dias_semana' or v_7b_q.chave like 'equipe_cadastro:chamada:%') then
          v_7b_ids := v_7b_ids - (jsonb_array_length(v_7b_ids) - 1);
        end if;
        -- (correção da revisão da 7b: fim)
        -- (correção 3) a forma curta (texto_curto, a que o Secretário cheio usa) leva o prazo de cada pergunta que vence e o
        -- "sigo assim": o registro não sabe qual das formas saiu e conta como vistas todas as pergunta_ids (agenda_fechamento_registrar),
        -- então a chamada vista só como "a equipe da agenda está certa?" ganhava o prazo de equipe_chamada_prazo_du dias úteis sem o dono
        -- ter lido o "sigo assim". A data é a que o vencimento grava: a chamada contada aqui (a 1ª da linha; a do "Também" não conta, achado
        -- 17), com o cadastro fora de desligado, vence em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (a rodada da semana
        -- grava o veto_ate no tique seguinte; já gravado, o dele); a dos dias da semana, com modo_dias fora de desligado, vence no prazo da
        -- semana dela (o dia do plano em perda_em, hora_do_plano − equipe_dias_fechar_antes: o passo fechar de agenda_equipe_semana), vista
        -- ou não. O telefone e o contato não vencem: como antes. A forma longa não muda.
        v_c3_ate := case
          when v_7b_q.chave like 'equipe_cadastro:chamada:%' and cf.modo_cadastro <> 'desligado' and v_7b_ids ? v_7b_q.id::text
            then coalesce(v_7b_q.veto_ate,
                          public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo', cf.equipe_chamada_prazo_du))
          when v_7b_q.tipo = 'dias_semana' and cf.modo_dias <> 'desligado' and v_7b_q.perda_em is not null
            then ((v_7b_q.perda_em + cf.hora_do_plano) - cf.equipe_dias_fechar_antes) at time zone 'America/Sao_Paulo' end;
        if v_c3_ate is not null then
          v_7b_curto := v_7b_curto || format(' — sem resposta até %s às %s, sigo assim',
                                             public._dia_curto((v_c3_ate at time zone 'America/Sao_Paulo')::date),
                                             to_char(v_c3_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
        end if;
        -- (correção 3: fim)
        v_7b_curtos := v_7b_curtos || v_7b_curto;
        -- (correção da revisão da 7b, achado 7) a chamada da 7a (sem opções) é do gestor que marca, também com o cadastro da 7b
        -- em teste: a de antes, já aberta e ligada, não vira teste (o dono deixava de vê-la)
        if v_7b_q.chave like 'equipe_cadastro:chamada:%' and cf.modo_cadastro <> 'ligado'
           and not exists (select 1 from public.agenda_perguntas p where p.id = v_7b_q.id and jsonb_array_length(p.opcoes) > 0) then
          v_7b_q.modo_agora := public._agenda_gestor_modo('marcar');
        end if;
        -- (correção da revisão da 7b: fim)
        v_7b_lig := v_7b_lig and v_7b_q.modo_agora = 'ligado';
        v_7b_perde := v_7b_perde or v_7b_q.mostrada_vezes = 0
                      or (v_7b_q.veto_ate is not null and (v_7b_q.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                      or v_7b_q.perda_em is not distinct from p_hoje;
      end loop;
      -- (7c P5, R5.4 item 4, R5.1-6, R5.10-7) as perguntas de quem faz o quê (habilidade), depois das da 7b: primeiro a da equipe
      -- (habilidade:equipe:…), depois as de OS (habilidade:os:…), e a mais antiga; só com o portão da 7c. A 1ª da linha vai inteira; as
      -- outras curtas, até c_max_perg ("Também: quem faz o quê (marquei: Alex instala sozinho; responda em *agenda pendências*)."; a de
      -- OS: "Também: Caio (OS-97173): falta quem comissiona Victron em todos os dias; quem pode? (responda em *agenda pendências*).").
      -- A da equipe que vai só como "Também" não conta como mostrada (sai de pergunta_ids: o achado 17 da 7b estendido) e sai inteira no
      -- fechamento em que vier primeiro; a de OS conta (vai com a pergunta toda, como o telefone e o contato). Na forma curta
      -- (texto_curto, a que o Secretário cheio usa — o registro não sabe qual forma saiu), a da equipe leva o que foi marcado e, quando é
      -- contada e vence (modo ligado), o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00,
      -- fica assim" (a data que _agenda_habilidade_vetos grava depois do registro: o veto_ate, ou _agenda_veto_ate do dia de hoje). O
      -- modo de cada uma é o de _agenda_modo_da_pergunta (a da equipe: modo_habilidade_propor; a de OS: modo_habilidade), que a linha não
      -- pode chamar (é só do service_role; a linha é lida pelo painel). A perda é a da (n): 75 enquanto alguma nunca foi vista inteira ou
      -- perde hoje.
      if v_7c_on then
        for v_7c_q in
          select x.id, x.tipo, x.chave, x.texto, x.modo, x.mostrada_vezes, x.veto_ate, x.perda_em,
                 coalesce(public._agenda_rotulo_da_os(x.service_order_id), '') as nome,
                 case when x.chave like 'habilidade:os:%' then cf.modo_habilidade else cf.modo_habilidade_propor end as modo_agora
            from public.agenda_perguntas x
           where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo = 'habilidade'
             and x.mostrada_vezes < cf.perguntas_vezes_max
             and not exists (select 1 from public.agenda_dono_avisos v
                              where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
           order by case when x.chave like 'habilidade:equipe:%' then 1 else 2 end, x.criada_em, x.id
        loop
          v_7c_eq := v_7c_q.chave like 'habilidade:equipe:%';
          -- o que foi marcado (as propostas vivas da pergunta, lidas sob a RLS de agenda_etiquetas) e o que a OS pede
          v_7c_marc := case when v_7c_eq then nullif(public._agenda_lista(array(
                         select public._agenda_nome_curto(py.name) || ' ' || split_part(public._agenda_etiqueta_texto(e.etiqueta, e.nivel), ':', 1)
                           from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id
                          where e.pergunta_id = v_7c_q.id and e.estado = 'proposta'
                          order by case e.etiqueta when 'instala' then 0 when 'ajudante' then 1 else 2 end, e.nivel desc,
                                   public._agenda_nome_curto(py.name), e.id), null), '') end;
          v_7c_exig := case when not v_7c_eq then substring(v_7c_q.texto from ': o serviço pede (.*), e nas próximas ') end;
          v_7b_curto := case when v_7c_eq then 'quem faz o quê' || coalesce(' — marquei: ' || v_7c_marc, '')
                             else format('%s: falta %s', v_7c_q.nome, coalesce(v_7c_exig, 'quem o serviço pede')) end;
          if v_7b_txt is null then
            v_7b_txt := 'Agenda: ' || v_7c_q.texto;
          else
            if v_7b_rest > 0 then
              v_7b_rest := v_7b_rest + 1;
              continue;
            end if;
            v_7b_item := case
              when v_7c_eq then format('Também: quem faz o quê (%sresponda em *agenda pendências*).',
                                       coalesce('marquei: ' || v_7c_marc || '; ', ''))
              else format('Também: %s: falta %s; quem pode? (responda em *agenda pendências*).', v_7c_q.nome,
                          coalesce(v_7c_exig, 'quem o serviço pede')) end;
            if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
              v_7b_rest := 1;
              continue;
            end if;
            v_7b_itens := v_7b_itens || v_7b_item;
          end if;
          v_7b_ids := v_7b_ids || to_jsonb(v_7c_q.id);
          if jsonb_array_length(v_7b_ids) > 1 and v_7c_eq then
            v_7b_ids := v_7b_ids - (jsonb_array_length(v_7b_ids) - 1);
          end if;
          if v_7c_eq and v_7c_q.modo = 'ligado' and v_7b_ids ? v_7c_q.id::text then
            v_7c_ate := coalesce(v_7c_q.veto_ate, public._agenda_veto_ate(p_hoje::timestamp at time zone 'America/Sao_Paulo'));
            v_7b_curto := v_7b_curto || format('; sem resposta até %s às %s, fica assim',
                                               public._dia_curto((v_7c_ate at time zone 'America/Sao_Paulo')::date),
                                               to_char(v_7c_ate at time zone 'America/Sao_Paulo', 'HH24:MI'));
          end if;
          v_7b_curtos := v_7b_curtos || v_7b_curto;
          v_7b_lig := v_7b_lig and v_7c_q.modo_agora = 'ligado';
          v_7b_perde := v_7b_perde or v_7c_q.mostrada_vezes = 0
                        or (v_7c_q.veto_ate is not null and (v_7c_q.veto_ate at time zone 'America/Sao_Paulo')::date = p_hoje)
                        or v_7c_q.perda_em is not distinct from p_hoje;
        end loop;
      end if;
      -- (7c: fim)
      -- (7c P8, R5.4 item 4, R5.2-2(c)) as perguntas das etapas (tarefa), depois das de quem faz o quê: primeiro a de quem faça a etapa de
      -- risco (tarefa:quem:<os>), depois a de prazo (tarefa:prazo:<os>), e a mais antiga; só com o portão das etapas. A 1ª da linha vai
      -- inteira; as outras curtas, até c_max_perg ("Também: Lenine: quem vai junto em "…"? (responda em *agenda pendências*)."). As duas
      -- contam como mostradas (vão com a pergunta toda, como a de OS de quem faz o quê). O modo é o de _agenda_modo_da_pergunta
      -- (modo_tarefas), que a linha não pode chamar. A de prazo cujo prazo (perda_em) é hoje ou o próximo dia útil perde hoje.
      if v_p8_on then
        for v_p8_q in
          select x.id, x.chave, x.texto, x.mostrada_vezes, x.perda_em,
                 coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                             join public.clients cl on cl.id = so.client_id where so.id = x.service_order_id),
                          public._agenda_rotulo_da_os(x.service_order_id), '') as cli
            from public.agenda_perguntas x
           where x.estado = 'aberta' and x.modo = m and not x.critica and x.tipo = 'tarefa'
             and x.mostrada_vezes < cf.perguntas_vezes_max
             and not exists (select 1 from public.agenda_dono_avisos v
                              where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
           order by case when x.chave like 'tarefa:quem:%' then 1 else 2 end, x.criada_em, x.id
        loop
          v_p8_quem := v_p8_q.chave like 'tarefa:quem:%';
          v_7b_curto := case when v_p8_quem then format('%s: quem vai junto%s?', v_p8_q.cli,
                                                         coalesce(' em ' || substring(v_p8_q.texto from '"[^"]+"'), ''))
                             else format('%s: as etapas não cabem até %s', v_p8_q.cli, public._dia_curto(v_p8_q.perda_em)) end;
          if v_7b_txt is null then
            v_7b_txt := 'Agenda: ' || v_p8_q.texto;
          else
            if v_7b_rest > 0 then
              v_7b_rest := v_7b_rest + 1;
              continue;
            end if;
            v_7b_item := format('Também: %s (responda em *agenda pendências*).', v_7b_curto);
            if char_length(array_to_string(array[v_7b_txt] || v_7b_itens || v_7b_item, ' ')) > c_max_perg - 32 then
              v_7b_rest := 1;
              continue;
            end if;
            v_7b_itens := v_7b_itens || v_7b_item;
          end if;
          v_7b_ids := v_7b_ids || to_jsonb(v_p8_q.id);
          v_7b_curtos := v_7b_curtos || v_7b_curto;
          v_7b_lig := v_7b_lig and cf.modo_tarefas = 'ligado';
          v_7b_perde := v_7b_perde or v_p8_q.mostrada_vezes = 0
                        or (not v_p8_quem and v_p8_q.perda_em is not null and v_p8_q.perda_em <= v_am1);
        end loop;
      end if;
      -- (7c: fim)
      continue when v_7b_txt is null;
      v_7b_l := array_to_string(array[v_7b_txt] || v_7b_itens, ' ')
                || case when v_7b_rest > 0 then format(' (e mais %s em *agenda equipe*)', v_7b_rest) else '' end;
      v_7b_curto := 'Agenda, equipe: ' || array_to_string(v_7b_curtos, '; ')
                    || case when right(v_7b_curtos[cardinality(v_7b_curtos)], 1) = '?' then '' else '.' end
                    || ' *agenda pendências* mostra.';
      v_out := v_out || (jsonb_build_object('tipo', 'pergunta', 'texto', v_7b_l, 'perda', case when v_7b_perde then 75 else 30 end,
        'pergunta_id', v_7b_ids ->> 0, 'pergunta_ids', v_7b_ids, 'acao_ids', '[]'::jsonb,
        'modo', case when m = 'ligado' and v_7b_lig then 'ligado' else 'sombra' end)
        || case when char_length(v_7b_curto) < char_length(v_7b_l) then jsonb_build_object('texto_curto', v_7b_curto)
                else '{}'::jsonb end);
    end loop;
  end if;
  -- FASE 7b: fim
  -- FASE 7c: (7c P5, R5.10-8) o portão da 7b volta a ser só o dela: a (e) exclui as perguntas da 7b só com ele (e as de quem faz o quê
  -- só com o da 7c, abaixo)
  v_7b_on := v_7c_7b;
  -- FASE 7c: fim
  -- (e) uma pergunta de fato, a que perde primeiro (cada pergunta aparece em até perguntas_vezes_max fechamentos)
  -- FASE 3: entram também concluir, entrega, equipe_resposta e diaria_ligar (não críticas)
  for m in select unnest(array['ligado', 'sombra']) loop
    select count(*) into v_n from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- FASE 7: (7a correção, achado 15) nem as perguntas do gestor que esperam o dono: elas vão na linha (m), acima
       and x.tipo not in ('situacao', 'estimativa', 'reestimar')
       -- FASE 7: fim
       -- FASE 7b: (7b P3, R4.2(d)) nem as perguntas da equipe: elas vão na linha (n), acima
       and not (v_7b_on and x.tipo in ('equipe_cadastro', 'dias_semana'))
       -- FASE 7b: fim
       -- FASE 7c: (7c P5, R5.4 item 4) nem as perguntas de quem faz o quê com a 7c fora de desligado: elas vão na linha (n), acima
       and not (v_7c_on and x.tipo = 'habilidade')
       -- FASE 7c: fim
       -- FASE 7c: (7c P8, R5.4 item 4) nem as perguntas das etapas com o modo_tarefas fora de desligado: elas vão na linha (n), acima
       and not (v_p8_on and x.tipo = 'tarefa')
       -- FASE 7c: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max;
    continue when v_n = 0;
    select x.* into q from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       -- FASE 7: (7a P7) nem a pergunta do gestor (situacao/estimativa) em que o dono já escolheu "eu digo os dias": o prazo
       -- dela não vale mais, e o texto o prometia (notas do P4, desvio 4)
       and not (x.tipo in ('situacao', 'estimativa') and x.opcao_escolhida is not null)
       -- FASE 7: fim
       -- FASE 7: (7a P11) nem a ficha_estimativa: ela tem a linha própria (l), acima
       and x.tipo <> 'ficha_estimativa'
       -- FASE 7: fim
       -- FASE 7: (7a correção, achado 15) nem as perguntas do gestor que esperam o dono: elas vão na linha (m), acima
       and x.tipo not in ('situacao', 'estimativa', 'reestimar')
       -- FASE 7: fim
       -- FASE 7b: (7b P3, R4.2(d)) nem as perguntas da equipe: elas vão na linha (n), acima
       and not (v_7b_on and x.tipo in ('equipe_cadastro', 'dias_semana'))
       -- FASE 7b: fim
       -- FASE 7c: (7c P5, R5.4 item 4) nem as perguntas de quem faz o quê com a 7c fora de desligado: elas vão na linha (n), acima
       and not (v_7c_on and x.tipo = 'habilidade')
       -- FASE 7c: fim
       -- FASE 7c: (7c P8, R5.4 item 4) nem as perguntas das etapas com o modo_tarefas fora de desligado: elas vão na linha (n), acima
       and not (v_p8_on and x.tipo = 'tarefa')
       -- FASE 7c: fim
       -- CORREÇÃO 29/10 (revisão): nem a pergunta que um aviso do gestor de hoje já levou ou está levando (na fila).
       and not exists (select 1 from public.agenda_dono_avisos v
                        where v.dia = p_hoje and v.estado in ('enfileirada', 'enviada') and x.id = any (v.pergunta_ids))
       -- CORREÇÃO 29/10 (revisão): fim
       and x.mostrada_vezes < cf.perguntas_vezes_max
     order by x.perda_em nulls last, x.criada_em, x.id limit 1;
    v_out := v_out || jsonb_build_object('tipo', 'pergunta',
      'texto', 'Agenda: ' || q.texto || case when v_n > 1 then format(' (e mais %s em *agenda pendências*)', v_n - 1) else '' end,
      'perda', 30, 'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 7c: (7c P8, R5.2-2(b), R5.10-6, -10, -13) (o) as etapas de quem não recebe pelo WhatsApp (sem telefone pela régua da 7a,
  -- _agenda_equipe_tem_telefone — a mesma do registro —, ou fora da lista da rotina) com etapa no plano de hoje ou do próximo dia útil: o
  -- que hoje devia ficar pronto (o dono passa e confere) e o que fazer amanhã, sem números (as listas do dia e a da OS numeram
  -- diferente), até c_max, cortando por etapa inteira ("e mais N"); o texto_curto para o Secretário cheio. Perda 75 só quando amanhã é
  -- o último dia de uma OS (a cobrança da véspera) ou volta primeiro uma pendente dita; senão 70 (a etapa de risco sozinha não sobe a
  -- perda). Tipo dia, sem pergunta: nada vence por ela. Em teste, modo sombra e "Em teste: " (vai ao detalhe, nunca ao texto do dono).
  -- Só com a porta das etapas aberta (o administrador ou o financeiro logado, ou sem login).
  if cf.modo_tarefas <> 'desligado' and (auth.uid() is null or public.is_admin_or_financial(auth.uid())) then
    for v_p8_pess in
      select x.payee_id, x.nome, public._agenda_equipe_tem_telefone(x.payee_id) as fone,
             exists (select 1 from public.agenda_equipe_contato c
                      where c.payee_id = x.payee_id and c.recebe_rotina and c.parou_em is null) as rotina
        from (select distinct a.payee_id, public._agenda_nome_curto(py.name) as nome
                from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
               where a.dia in (p_hoje, v_am1) and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
                 and a.payee_id is distinct from public._agenda_dono(null)) x
       order by x.nome, x.payee_id
    loop
      continue when v_p8_pess.fone and v_p8_pess.rotina;
      v_p8_h := public._agenda_tarefas_da_pessoa(v_p8_pess.payee_id, p_hoje, p_hoje);
      v_p8_a := public._agenda_tarefas_da_pessoa(v_p8_pess.payee_id, v_am1, p_hoje);
      -- hoje: o que terminava e ainda não tem resultado (uma vez por etapa)
      v_p8_hi := coalesce((select jsonb_agg(i order by (i ->> 'n')::int) from jsonb_array_elements(v_p8_h -> 'itens') i
                            where (i ->> 'termina')::boolean and i -> 'resultado' = 'null'::jsonb
                              and not exists (select 1 from jsonb_array_elements(v_p8_hoje) j where j ->> 'tarefa' = i ->> 'tarefa')),
                           '[]'::jsonb);
      -- amanhã: o que a pessoa faz, por OS, com o último dia e a pendente dita que volta primeiro
      v_p8_ai := coalesce((select jsonb_agg(i || jsonb_build_object('nome', v_p8_pess.nome, 'payee', v_p8_pess.payee_id,
                                  'com', case when (i ->> 'com_dono')::boolean then 'você' end,
                                  'ultimo', (v_p8_a -> 'ultimo_dia') @> jsonb_build_array(jsonb_build_object('os', i ->> 'os')),
                                  'pdita', exists (select 1 from public.os_tarefas t where t.id = (i ->> 'tarefa')::uuid
                                                      and t.estado = 'viva' and t.pendente_vezes > 0))
                                order by (i ->> 'n')::int)
                           from jsonb_array_elements(v_p8_a -> 'itens') i), '[]'::jsonb);
      -- só quem tem o que conferir hoje ou o que fazer amanhã entra no "Etapas (… não tem telefone …)"
      continue when jsonb_array_length(v_p8_hi) = 0 and jsonb_array_length(v_p8_ai) = 0;
      v_p8_nomes := v_p8_nomes || v_p8_pess.nome;
      v_p8_nfone := coalesce(v_p8_nfone, 0) + case when v_p8_pess.fone then 0 else 1 end;
      v_p8_nrot := coalesce(v_p8_nrot, 0) + case when v_p8_pess.rotina then 0 else 1 end;
      v_p8_hoje := v_p8_hoje || v_p8_hi;
      v_p8_amanha := v_p8_amanha || v_p8_ai;
    end loop;
    if jsonb_array_length(v_p8_hoje) > 0 or jsonb_array_length(v_p8_amanha) > 0 then
      v_p8_dia := case when v_am1 = p_hoje + 1 then 'Amanhã (' || public._dia_curto(v_am1) || ')'
                       else public._agenda_maiuscula(public._dia_curto(v_am1)) end;
      -- monta com até v_p8_k etapas por lista; corta por etapa inteira até caber em c_max
      v_p8_k := 5;
      loop
        v_p8_txt := format('Etapas (%s %s: quem passa e confere é você).', public._agenda_lista(v_p8_nomes, null),
                           case when v_p8_nfone = cardinality(v_p8_nomes)
                                  then case when cardinality(v_p8_nomes) = 1 then 'não tem telefone' else 'não têm telefone' end
                                when v_p8_nrot = cardinality(v_p8_nomes)
                                  then case when cardinality(v_p8_nomes) = 1 then 'não está na rotina da equipe' else 'não estão na rotina da equipe' end
                                else 'não recebem pelo WhatsApp' end);
        for v_p8_g in select i ->> 'cliente' as cli, min((i ->> 'n')::int) as o,
                             jsonb_agg(i order by (i ->> 'n')::int) as its
                        from jsonb_array_elements(v_p8_hoje) i group by i ->> 'cliente' order by 2 loop
          v_p8_txt := v_p8_txt || format(' Hoje no %s devia ficar pronto: %s.', v_p8_g.cli,
                                         public._agenda_tarefas_lista_texto(v_p8_g.its, v_p8_k, null, false, false));
        end loop;
        if jsonb_array_length(v_p8_hoje) > 0 then
          v_p8_txt := v_p8_txt || format(' Se faltou alguma, me diga qual (ex.: no %s falta "%s").', v_p8_hoje -> 0 ->> 'cliente',
                                         lower(left(v_p8_hoje -> 0 ->> 'texto', 1)) || substr(v_p8_hoje -> 0 ->> 'texto', 2));
        end if;
        for v_p8_g in select i ->> 'nome' as nome, i ->> 'cliente' as cli, min((i ->> 'n')::int) as o,
                             bool_or((i ->> 'ultimo')::boolean) as ult, jsonb_agg(i order by (i ->> 'n')::int) as its
                        from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                       order by i ->> 'nome', 3 loop
          v_p8_txt := v_p8_txt || format(' %s, %s no %s: %s.', v_p8_dia, v_p8_g.nome, v_p8_g.cli,
                                         public._agenda_tarefas_lista_texto(v_p8_g.its, v_p8_k, null, true, false))
                      || case when v_p8_g.ult then ' É o último dia: tem que ficar tudo pronto.' else '' end;
        end loop;
        v_p8_txt := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end || v_p8_txt;
        exit when char_length(v_p8_txt) <= c_max or v_p8_k = 1;
        v_p8_k := v_p8_k - 1;
      end loop;
      v_p8_txt := public._agenda_corta(v_p8_txt, c_max);
      -- a forma curta (o Secretário cheio)
      v_p8_parte := array(select case when bool_or((i ->> 'ultimo')::boolean)
                                      then format('amanhã é o último dia do %s (%s, %s)', i ->> 'cliente', i ->> 'nome',
                                                  public._agenda_plural(count(*)::int, 'etapa', 'etapas'))
                                      else format('amanhã, %s no %s (%s)', i ->> 'nome', i ->> 'cliente',
                                                  public._agenda_plural(count(*)::int, 'etapa', 'etapas')) end
                            from jsonb_array_elements(v_p8_amanha) i group by i ->> 'nome', i ->> 'payee', i ->> 'cliente'
                           order by i ->> 'nome', min((i ->> 'n')::int))
                  || case when jsonb_array_length(v_p8_hoje) > 0
                          then array[format('hoje, %s para conferir', jsonb_array_length(v_p8_hoje))] else '{}'::text[] end;
      v_p8_curto := case when cf.modo_tarefas = 'ligado' then '' else 'Em teste: ' end
                    || 'Etapas: ' || array_to_string(v_p8_parte, '; ') || '.'
                    || case when jsonb_array_length(v_p8_amanha) > 0
                            then format(' Pergunte o que o %s faz amanhã.', v_p8_amanha -> 0 ->> 'nome') else '' end;
      v_p8_alta := exists (select 1 from jsonb_array_elements(v_p8_amanha) i where (i ->> 'ultimo')::boolean or (i ->> 'pdita')::boolean);
      v_out := v_out || (jsonb_build_object('tipo', 'dia', 'texto', v_p8_txt, 'perda', case when v_p8_alta then 75 else 70 end,
        'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_tarefas = 'ligado' then 'ligado' else 'sombra' end)
        || case when char_length(v_p8_curto) < char_length(v_p8_txt) then jsonb_build_object('texto_curto', v_p8_curto)
                else '{}'::jsonb end);
    end if;
  end if;
  -- FASE 7c: fim
  -- FASE 3 (f): o PPC no último dia útil da semana (sexta; com feriado, o dia útil antes), se a semana teve compromisso
  v_ppc := public.agenda_ppc(p_hoje, p_hoje);
  if (v_ppc ->> 'ultimo_dia_util')::boolean and (v_ppc ->> 'compromissos')::int > 0 and v_ppc ->> 'linha' is not null then
    v_out := v_out || jsonb_build_object('tipo', 'ppc', 'texto', public._agenda_corta(v_ppc ->> 'linha', c_max), 'perda', 55,
      'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end if;

  -- FASE 3 (g): a comissão do mês que fechou, no 1º dia útil do mês (só a conta: nada é pago). Quem não pode ver a
  -- comissão (42501) não ganha a linha.
  if p_hoje = public.agenda_somar_du(make_date(extract(year from p_hoje)::int, extract(month from p_hoje)::int, 1), 0) then
    begin
      v_com := public.comissao_resumo_do_mes(null, p_hoje);
    exception when sqlstate '42501' then
      v_com := null;
    end;
    if coalesce((v_com ->> 'primeiro_dia_util')::boolean, false) and nullif(v_com ->> 'linha', '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'comissao', 'texto', v_com ->> 'linha', 'perda', 20,
        'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;

  -- FASE 7: (7a P7) (i) o "eu marcaria assim" do gestor em teste (spec §6.1): com o modo marcar em sombra, o texto_sombra do
  -- diário de hoje (a rodada do gestor das 16:52 o grava), perda 65, com o modo da vigia (o dono lê de verdade o que o gestor
  -- faria). (j) As compras da semana (agenda_gestor_dia.compras de hoje, que o P10 grava, [{texto, compre_ate, urgente}]): perda
  -- 80 com alguma compra urgente (AG7-07: o serviço começa a menos de compra_urgente_du dias úteis — vai como decisão), 65 com
  -- "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis; sem nada disso, nenhuma linha. O modo é o do compre_ate.
  if public._agenda_gestor_modo('marcar') = 'sombra' then
    select g.texto_sombra into v_f7_txt from public.agenda_gestor_dia g where g.dia = p_hoje;
    if nullif(btrim(v_f7_txt), '') is not null then
      -- (7a correção, achado 14) em teste, perda 25: abaixo de toda linha de verdade (só a comissão é menor) — a linha de teste
      -- não tira o lugar da semana publicada, da diária, da conclusão nem da pergunta que o dono precisa ver
      v_out := v_out || jsonb_build_object('tipo', 'gestor', 'texto', v_f7_txt, 'perda', 25, 'pergunta_id', null,
        'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  select g.compras into v_f7_cmp from public.agenda_gestor_dia g where g.dia = p_hoje;
  if jsonb_array_length(coalesce(v_f7_cmp, '[]'::jsonb)) > 0 then
    select min((e ->> 'compre_ate')::date), coalesce(bool_or((e ->> 'urgente')::boolean), false)
      into v_f7_min, v_f7_urg from jsonb_array_elements(v_f7_cmp) e;
    -- (7a correção, achado 19) o "compre até" de hoje (ou vencido, que comprando hoje ainda chega) é decisão de hoje: perda 80
    v_f7_perda := case when v_f7_urg or (v_f7_min is not null and v_f7_min <= p_hoje) then 80
                       when v_f7_min is not null and v_f7_min <= v_am1 then 65
                       when v_f7_min is not null and v_f7_min <= public.agenda_somar_du(p_hoje, cf.compras_aviso_du) then 45 end;
    v_f7_txt := array_to_string(array(select btrim(e ->> 'texto') from jsonb_array_elements(v_f7_cmp) with ordinality t(e, o)
                                       where nullif(btrim(e ->> 'texto'), '') is not null order by o), ' ');
    if v_f7_perda is not null and nullif(v_f7_txt, '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'compras', 'texto', public._agenda_corta('Compras: ' || v_f7_txt, c_max),
        'perda', v_f7_perda, 'pergunta_id', null, 'acao_ids', '[]'::jsonb,
        'modo', case when public._agenda_gestor_modo('compre_ate') = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;
  -- FASE 7: fim
  -- FASE 5: (h) a mensagem ao cliente, só com modo_cliente ligado: a que espera *manda cliente* e sai até o próximo dia de
  -- janela (perda 75; até 600 caracteres, c_max_cliente de _agenda_cliente_fechamento) e o que sai sozinho amanhã (perda 40,
  -- com *segura cliente*). As críticas (cliente_aviso) já entram pela linha decisao; o que saiu, pela linha mudancas.
  if cf.modo_cliente = 'ligado' then
    v_out := v_out || public._agenda_cliente_fechamento(p_hoje);
  end if;
  -- FASE 5: fim
  return coalesce((select jsonb_agg(x order by (x ->> 'perda')::int desc, x ->> 'tipo', x ->> 'texto')
                     from jsonb_array_elements(v_out) x), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_linhas_do_fechamento(date) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar). FASE 5 (P5): cliente (só com modo_cliente ligado; _agenda_cliente_fechamento) — perda 75 com a mensagem que espera *manda cliente* e sai até o próximo dia de janela (a 1ª inteira, até 600 caracteres; acima disso o texto da mensagem é cortado em 300 e *agenda clientes* mostra inteira), perda 40 com o que sai sozinho amanhã e *segura cliente <nome>*. CORREÇÃO 29/10 (revisão): a pergunta de fato (e) não repete a que um aviso do gestor de hoje já levou ou está levando (agenda_dono_avisos enfileirada ou enviada): a pergunta sai uma vez por dia. FASE 7 (7a P7, spec §5.7 e §6.1): (i) com o gestor que marca em teste (_agenda_gestor_modo(''marcar'') = ''sombra''), a linha gestor — o "eu marcaria assim" do diário de hoje (agenda_gestor_dia.texto_sombra, ≤ 640: "Agenda em teste (nada mudou): eu marcaria assim — …"), perda 65, modo = o da vigia; (j) a linha compras — as compras da semana do diário de hoje (agenda_gestor_dia.compras [{texto, compre_ate, urgente}], que o P10 grava): perda 80 com compra urgente (AG7-07: vai como decisão), 65 com "compre até" hoje ou amanhã, 45 até compras_aviso_du dias úteis, modo = o do compre_ate; (k) a pergunta situacao/estimativa em que o dono já escolheu "eu digo os dias" (opcao_escolhida) não volta como linha pergunta (o prazo dela não vale mais). Sem o gestor em teste e sem compras, a saída de antes, byte a byte. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11): (l) a pergunta ficha_estimativa aberta de hoje (veto_ate hoje: a ficha das 19:30 de um dia pela estimativa, na janela de veto do ligar) numa linha própria, tipo pergunta, perda 75, com o pergunta_id (o fechamento que sai a conta como mostrada), uma por pessoa, modo = o da vigia; a linha (e) não a repete. Sem essa pergunta, a saída de antes, byte a byte. CORREÇÃO DA 7a (revisão da etapa): (achados 15 e 18) (m), no lugar da (l): as perguntas do gestor que esperam o dono — a ficha_estimativa de hoje, situacao, estimativa e reestimar — numa linha só, tipo pergunta: a 1ª (a ficha primeiro, depois a de prazo mais perto) com o texto inteiro, as outras curtas e agrupadas pelo prazo ("Também, sem resposta até ter 03/11 18:00: Nelson (OS-00112) 4 dias; …"; sem prazo: "Espero você: …"), até 600 caracteres, com pergunta_id (a 1ª) e pergunta_ids (todas as que a linha mostra: o fechamento que sai as conta como mostradas); perda 75 com alguma de prazo (ela perde no prazo), 30 sem; a linha (e) não as repete; (achado 14) a linha gestor de teste ("eu marcaria assim") vai com perda 25, abaixo de toda linha de verdade (só a comissão é menor); (achado 19) as compras com "compre até" hoje ou já vencido (comprando hoje ainda chega) vão como decisão, perda 80. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; os achados 15/18 de novo): a linha (m) das perguntas do gestor com prazo vai com perda 76 (ganha o desempate das que perdem hoje: antes perdia para a mensagem ao cliente pelo tipo e saía primeiro no corte de 1.000 do fechamento); as sem prazo dizem o porquê ("Espero você (não marco sozinho): Giancarlo (OS-00130)."); (o corte de 1.000) a linha (m) leva também texto_curto, com as MESMAS perguntas: a ficha sem as opções e cada uma pelo prazo e pelo que o gestor faz sem resposta ("Agenda: Sem resposta até ter 03/11 18:00, conto: Nelson (OS-00112) 4 dias; Flávio (OS-00104) 3,5 dias. Espero você (não marco sozinho): Giancarlo (OS-00130).") — o Secretário cheio a usa antes de tirar a linha. FASE 7b (P3, R4.2(d)): com modo_dias ou modo_cadastro fora de desligado, (n) a equipe — as perguntas abertas da equipe (a chamada equipe_cadastro:chamada, a dias_semana do dono, o telefone e o contato; não críticas, mostradas menos de perguntas_vezes_max vezes, fora as que um aviso de hoje levou) numa linha só, tipo pergunta, nesta ordem e depois a mais antiga: a 1ª com o texto inteiro, as outras curtas ("Também: o telefone do Alex (sem ele não mando a ficha)."; "Também: Mateus tem telefone; ponho na rotina? Responda 1 ou 2 em *agenda pendências*."; "Também: os dias da semana de 16/11 (responda em *agenda pendências*).") até 600 caracteres e o resto "(e mais N em *agenda equipe*)"; pergunta_id = a 1ª e pergunta_ids = todas as que a linha mostra (o fechamento que sai as conta como mostradas); perda 75 enquanto alguma nunca foi mostrada ou perde hoje (veto_ate ou perda_em de hoje), senão 30; modo ligado só com a pergunta em ligado e o modo dela ligado; texto_curto com as mesmas perguntas, só pelo nome ("Agenda, equipe: a equipe da agenda está certa?; o telefone do Alex. *agenda pendências* mostra."). A pergunta de fato (e) não as repete. Com os dois modos desligados, a saída de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 7 e 17): na linha (n) da equipe, a chamada e a pergunta dos dias que vão só como "Também: … (responda em *agenda pendências*)" ficam fora de pergunta_ids (não contam como mostradas; saem inteiras no fechamento em que vierem primeiro); a chamada da 7a (sem opções) usa o modo do gestor que marca, também com o cadastro da 7b em teste. CORREÇÃO 3 DA 7b (o R5.9 da spec da 7c; o R5.10-7): na linha (n) da equipe, a forma curta (texto_curto, a que o Secretário cheio usa, e o registro conta as pergunta_ids da linha sem saber qual forma saiu) leva, em cada pergunta que vence, o prazo e o "sigo assim" — "Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim. *agenda pendências* mostra." —, com a data que o vencimento grava: a chamada contada na linha, com o cadastro fora de desligado, em _agenda_veto_ate(o dia do registro, equipe_chamada_prazo_du) (ou o veto_ate já gravado); a dos dias da semana, com modo_dias fora de desligado, no prazo da semana dela (perda_em, hora_do_plano − equipe_dias_fechar_antes). O telefone e o contato não vencem: como antes. A forma longa e o resto, byte a byte. FASE 7c (P5, R5.4 item 4, R5.1-6, R5.10-7/-8): o portão da linha (n) passa a "a 7b (modo_dias ou modo_cadastro) OU a 7c (modo_habilidade_propor ou modo_habilidade) fora de desligado"; dentro dela, as perguntas da 7b só com o portão da 7b e, depois delas, as de quem faz o quê (habilidade: primeiro a habilidade:equipe, depois as habilidade:os) só com o da 7c, com o modo de _agenda_modo_da_pergunta (a da equipe: modo_habilidade_propor; a de OS: modo_habilidade). A da equipe que vai só como "Também: quem faz o quê (marquei: Alex instala sozinho; responda em *agenda pendências*)." fica fora de pergunta_ids (não conta como vista); a de OS ("Também: Caio (OS-97173): falta quem comissiona Victron em todos os dias; quem pode? (responda em *agenda pendências*).") conta. A forma curta leva o que foi marcado e, na da equipe contada e ligada, o prazo: "quem faz o quê — marquei: Alex instala sozinho; sem resposta até qua 04/11 às 18:00, fica assim" (o veto_ate, ou _agenda_veto_ate do dia de hoje: a data que _agenda_habilidade_vetos grava depois do registro). A pergunta de fato (e) exclui as da 7b só com o portão da 7b e as de quem faz o quê só com o da 7c. Com os modos da 7c desligados, a saída de antes, byte a byte (com a 7b desligada e em teste). FASE 7c (P8, R5.4 item 4, R5.2-2(b) e (c)): com modo_tarefas fora de desligado, a linha (n) leva também as perguntas das etapas (tarefa:quem:<os>, depois tarefa:prazo:<os>; a de prazo que vence hoje ou no próximo dia útil perde hoje), só com o portão delas, e a (e) não as repete; e a linha (o) das etapas (tipo dia; até 480, sem números): a quem não recebe pelo WhatsApp (sem telefone pela régua da 7a ou fora da rotina) com etapa hoje ou no próximo dia útil — "Etapas (Alex não tem telefone: quem passa e confere é você). Hoje no Lenine devia ficar pronto: …. Se faltou alguma, me diga qual (…). Amanhã (qui 05/11), Alex no Lenine: Terminar: …; … — com você. É o último dia: tem que ficar tudo pronto." —, texto_curto "Etapas: amanhã é o último dia do Lenine (Alex, 2 etapas); hoje, 2 para conferir. Pergunte o que o Alex faz amanhã.", perda 75 só com o último dia de uma OS amanhã ou com uma pendente dita que volta primeiro (senão 70), sem pergunta; em teste, modo sombra e "Em teste: ". Com modo_tarefas desligado, a de antes, byte a byte.';

-- ── 7. Portas ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- As leituras com porta (definer, a porta dentro: com login, só admin/financeiro; sem login, só o service_role): o painel (authenticated)
-- e o service_role. As puras de texto que as leituras invoker (agenda_dia_da_pessoa, a linha do fechamento) e o CHECK chamam:
-- authenticated e service_role. A RPC da ferramenta: authenticated (o painel) e service_role (o WhatsApp), quem confere o cargo é o
-- _autor_da_agenda. A rodada: só service_role. A frase da releitura: só service_role (como _agenda_rascunho_frase). As peças de dentro
-- (a sincronização, o planejar, o congelar, o registrar, o conferir, a leitura da resposta, as exceções, o casar, o *grava* da linha e os 2
-- gatilhos): ninguém, nem service_role (só as definer da agenda as chamam). As 9 recriadas mantêm as portas delas (create or replace não
-- muda a ACL). E a régua do telefone da 7a ganha o grant de quem lê a linha (o) (R5.2-1, R5.10-13: ela é invoker e lê payees e
-- app_settings sob a RLS; anon continua sem acesso).
revoke all on function public._agenda_tarefas_fases_ok(jsonb), public._agenda_tarefa_texto(text, integer),
  public._agenda_tarefa_fase(text, jsonb), public._agenda_tarefa_datas(date, date),
  public._agenda_tarefas_lista_texto(jsonb, integer, integer, boolean, boolean)
  from public, anon;
grant execute on function public._agenda_tarefas_fases_ok(jsonb), public._agenda_tarefa_texto(text, integer),
  public._agenda_tarefa_fase(text, jsonb), public._agenda_tarefa_datas(date, date),
  public._agenda_tarefas_lista_texto(jsonb, integer, integer, boolean, boolean)
  to authenticated, service_role;
revoke all on function public.os_tarefas_fonte(uuid, date), public.os_tarefas_da_os(uuid, date),
  public.agenda_tarefas_medidas(date, date, date), public._agenda_tarefas_da_pessoa(uuid, date, date)
  from public, anon;
grant execute on function public.os_tarefas_fonte(uuid, date), public.os_tarefas_da_os(uuid, date),
  public.agenda_tarefas_medidas(date, date, date), public._agenda_tarefas_da_pessoa(uuid, date, date)
  to authenticated, service_role;
revoke all on function public.agenda_rascunho_etapa(uuid, text, text, text, text, text, text[], text, date) from public, anon;
grant execute on function public.agenda_rascunho_etapa(uuid, text, text, text, text, text, text[], text, date)
  to authenticated, service_role;
revoke all on function public.agenda_tarefas_rodar(date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_tarefas_rodar(date, timestamptz) to service_role;
revoke all on function public._agenda_etapa_frase(jsonb) from public, anon, authenticated;
grant execute on function public._agenda_etapa_frase(jsonb) to service_role;
revoke all on function
  public._agenda_tarefas_sincronizar(uuid, date, timestamptz),
  public._agenda_tarefas_planejar(uuid, date, text),
  public._agenda_tarefas_texto_confere(text, jsonb),
  public._agenda_tarefas_congelar(date, timestamptz),
  public._agenda_tarefas_registrar(uuid[], text, text, text, uuid, timestamptz),
  public._agenda_tarefas_conferir(date, timestamptz),
  public._agenda_ler_tarefas_da_resposta(text, jsonb),
  public._agenda_tarefas_excecoes(date, timestamptz, uuid[]),
  public._agenda_tarefa_casar(uuid, text),
  public._agenda_aplicar_etapa(uuid, jsonb, text, date, timestamptz),
  public._os_tarefas_so_muda(),
  public._os_tarefas_dia_so_muda()
  from public, anon, authenticated, service_role;
grant execute on function public._agenda_equipe_tem_telefone(uuid) to authenticated, service_role;
