-- Agenda de Produção, Fase 3 ("A execução: equipe, diária, conclusão e telas"), pacote P1: a base — os parâmetros e
-- os modos novos, as colunas, as 4 tabelas e o gatilho da entrega.
-- Spec: scratchpad agenda-pesquisa/spec-fase3.md (§3, §4). Decisões do dono 23/10 (Autonomia, Rotina com a equipe,
-- Comissão). Depende da Fase 1 inteira (20261024160000..161000) e da Fase 2 inteira (20261025100000..101000).
--
-- ═══ DDL — OK NOMEADO ═══ (4 tabelas novas, vazias, mais a linha de comissao_config; 16 parâmetros em agenda_config e
-- 10 colunas novas em 5 tabelas, todas com DEFAULT ou nulas; 1 gatilho novo em service_orders)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: na Fase 3 o gestor passa a cuidar da execução — confirma a equipe na véspera pelo WhatsApp do Roberto,
-- lança a diária quando o técnico e o plano batem, conclui e entrega a OS pelo mesmo caminho da tela e calcula a
-- comissão "o maior dos dois" (só a conta, nunca o pagamento). Esta migration só cria o lugar de cada coisa; quem
-- escreve são as RPCs das próximas migrations da fase. Tudo nasce desligado e a migration de dado 20261026101000
-- (P7, OK nomeado) põe a equipe e a diária em sombra.
--
-- O QUE MUDA:
--   1. agenda_config: modo_diaria (a linha nasce 'desligado'; o DEFAULT da coluna vira 'sombra', como a Fase 2 fez com
--      modo_proposta e modo_vigia) e 15 parâmetros da rotina da equipe, da diária, da entrega, da carona, da carteira e
--      do PPC, cada um com CHECK por nome. O DEFAULT é o único lugar do número. O comentário de modo_equipe passa a
--      dizer o que cada modo faz na Fase 3.
--   2. service_orders.delivered_at (concluído ≠ entregue), com o CHECK "entrega só depois da conclusão" e o gatilho
--      trg_so_entrega_pela_porta: fora da porta (agenda.porta), ninguém escreve a entrega, em nenhum modo. O CHECK
--      também vale ao contrário: com a entrega gravada, o check_out_at não volta a nulo (quem limpar a saída de uma OS
--      entregue limpa a entrega junto, pela porta).
--   3. agenda_alocacoes.work_shift_id (o meio-dia que virou diária) e resultado_via 'equipe' (a resposta do técnico).
--   4. agenda_acoes: payee_id, work_shift_id, receivable_ids; tipos 'diaria', 'concluir', 'entregar', 'equipe'; origem
--      'equipe'.
--   5. agenda_perguntas: payee_id, carona_em; tipos 'diaria' (CRÍTICA), 'diaria_ligar', 'equipe_resposta', 'concluir',
--      'entrega'; a coluna gerada critica passa a incluir 'diaria' (o gatilho agenda_acoes_critica_decidida da Fase 2
--      passa a valer para a diária que diverge).
--   6. agenda_vigia_rodadas: rotina ('vigia' | 'rotina'), modo_equipe, modo_diaria.
--   7. Quatro tabelas: agenda_equipe_contato (quem recebe a rotina: só pela regra ou pelo dono), agenda_equipe_mensagens
--      (toda mensagem à equipe, mandada ou só registrada em sombra, e a resposta; NUNCA apagada), agenda_intervencoes_do_dono
--      (o dono foi sem estar previsto: o insumo do aprendizado da presença) e comissao_config (os parâmetros da comissão,
--      com o pagamento DESLIGADO por construção: CHECK pagamento = 'desligado').
--   8. Portas: RLS ligada; só leitura TO authenticated (admin/financeiro); revoke de public, anon e authenticated; escrita
--      só pelas RPCs security definer das próximas migrations (e por service_role).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase3_base.sql):
--   · critica por SET EXPRESSION, não por drop/add. A spec mandava apagar e recriar a coluna (e as duas constraints que
--     dependem dela) porque "Postgres anterior ao 17 não altera expressão de coluna gerada"; e deixava a alternativa
--     para o pacote decidir pela versão. Produção é Postgres 17.6 (SELECT de 24/10, server_version_num 170006) e a
--     bancada é 18.3: os dois têm ALTER COLUMN … SET EXPRESSION, que mantém a posição da coluna, revalida e mantém
--     critica_tem_opcoes e critica_decidida com o mesmo nome. Num Postgres anterior ao 17 a migration para com a
--     frase, em vez de seguir por um caminho que nunca rodou.
--   · _agenda_perguntas_antes e _agenda_acoes_so_desfaz (Fase 2) recriadas, com o corpo de 20261025100000 (a única que
--     as define). Além do carona_em que a spec pedia, as FKs novas ON DELETE SET NULL (payee_id nas duas; work_shift_id
--     nas ações) entram na lista do que pode virar nulo: sem isso, apagar uma diária no Financeiro (ou um favorecido)
--     ligado a uma ação da agenda falharia com "A ação registrada não muda" — o mesmo defeito que a Fase 2 corrigiu
--     para autor, OS e proposta.
--   · As horas da rotina "dentro da janela" ficam de equipe_janela_inicio até ANTES de equipe_janela_fim: a mensagem
--     marcada no último minuto da janela já sairia fora dela na 1ª nova tentativa da fila.
--   · agenda_vigia_rodadas ganhou CHECK nos dois modos novos (nulos nas rodadas de antes), como os modos da Fase 2.
--   · O gatilho da entrega vale também no INSERT (a spec dizia BEFORE UPDATE OF delivered_at): uma OS que nasce já
--     entregue (cópia da linha inteira de outra) entraria sem a porta. Hoje nenhum caminho insere OS com a coluna, que é
--     nova; OS nova sem entrega passa como sempre.
--   · agenda_equipe_mensagens.dedupe_key: o comentário diz que, em sombra, a chave termina em ":sombra". A tabela deixa
--     a mesma mensagem existir nos dois modos (o índice único inclui o modo), e a chave única sem o modo impediria a
--     de verdade no dia em que o modo liga.
--
-- O QUE NÃO MUDA: nenhum comportamento. Nenhuma função lê os parâmetros nem as tabelas novas ainda; os modos novos nascem
-- desligados na linha; o gatilho da entrega só recusa escrever uma coluna que ninguém escreve hoje. Nenhum cron, nenhuma
-- tela, nenhuma função de borda.
--
-- ORDEM DE LIGAR: depois das Fases 1 e 2 inteiras aplicadas (fila-do-dono/fase1-oks.md e fase2-oks.md); antes de
-- 20261026100100 (a porta completa, que escreve delivered_at e os recebíveis em agenda_acoes). Aplicar sozinha não muda
-- nada para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase3_base.sql (begin/rollback; cada CHECK recusa uma linha errada,
-- critica com 'diaria', delivered_at fora da porta recusado, as tabelas novas não se apagam, RLS, anon sem privilégio).
-- Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261026100000
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261026100000_agenda_fase3_tabelas.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261026100000', 'agenda_fase3_tabelas');"
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$ (os de lista fechada: drop if exists + add), a
-- expressão de critica só se ainda não tem 'diaria', create table/index if not exists, create or replace function,
-- drop trigger/policy if exists + create, insert on conflict do nothing.

-- ── 1. Parâmetros e o modo da diária ────────────────────────────────────────────────────────────────────
alter table public.agenda_config
  add column if not exists modo_diaria              text         not null default 'desligado',
  add column if not exists equipe_janela_inicio     time         not null default '07:30',
  add column if not exists equipe_janela_fim        time         not null default '20:00',
  add column if not exists equipe_hora_ficha        time         not null default '19:30',
  add column if not exists equipe_hora_confirmar    time         not null default '07:45',
  add column if not exists equipe_silencio_ate      time         not null default '09:00',
  add column if not exists equipe_hora_como_foi     time         not null default '17:00',
  add column if not exists equipe_proativas_dia_max smallint     not null default 2,
  add column if not exists equipe_respostas_dia_max smallint     not null default 4,
  add column if not exists equipe_resposta_validade interval     not null default '14 hours',
  add column if not exists diaria_janela_dias       smallint     not null default 7,
  add column if not exists entrega_aviso_du         smallint     not null default 5,
  add column if not exists carona_por_os_dias       smallint     not null default 7,
  add column if not exists carteira_laranja_du      smallint     not null default 5,
  add column if not exists carteira_vermelho_du     smallint     not null default 20,
  add column if not exists ppc_meta                 numeric(3,2) not null default 0.70;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_modo_diaria_check',              'check (modo_diaria in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_equipe_janela_inicio_check',     'check (equipe_janela_inicio between time ''06:00'' and time ''09:00'')'),
      ('agenda_config_equipe_janela_fim_check',        'check (equipe_janela_fim between time ''18:00'' and time ''21:00'')'),
      ('agenda_config_equipe_hora_ficha_check',        'check (equipe_hora_ficha >= equipe_janela_inicio and equipe_hora_ficha < equipe_janela_fim)'),
      ('agenda_config_equipe_hora_confirmar_check',    'check (equipe_hora_confirmar >= equipe_janela_inicio and equipe_hora_confirmar < equipe_janela_fim)'),
      ('agenda_config_equipe_hora_como_foi_check',     'check (equipe_hora_como_foi >= equipe_janela_inicio and equipe_hora_como_foi < equipe_janela_fim)'),
      ('agenda_config_equipe_silencio_ate_check',      'check (equipe_silencio_ate >= equipe_hora_confirmar + interval ''30 minutes'' and equipe_silencio_ate <= time ''11:00'')'),
      ('agenda_config_equipe_proativas_dia_max_check', 'check (equipe_proativas_dia_max between 1 and 3)'),
      ('agenda_config_equipe_respostas_dia_max_check', 'check (equipe_respostas_dia_max between 1 and 6)'),
      ('agenda_config_equipe_resposta_validade_check', 'check (equipe_resposta_validade between interval ''2 hours'' and interval ''24 hours'')'),
      ('agenda_config_diaria_janela_dias_check',       'check (diaria_janela_dias between 1 and 14)'),
      ('agenda_config_entrega_aviso_du_check',         'check (entrega_aviso_du between 1 and 15)'),
      ('agenda_config_carona_por_os_dias_check',       'check (carona_por_os_dias between 1 and 14)'),
      ('agenda_config_carteira_laranja_du_check',      'check (carteira_laranja_du between 1 and 15)'),
      ('agenda_config_carteira_vermelho_du_check',     'check (carteira_vermelho_du between carteira_laranja_du + 1 and 60)'),
      ('agenda_config_ppc_meta_check',                 'check (ppc_meta between 0.5 and 0.95)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

-- Como a Fase 2: a estrutura não muda comportamento. A linha que já existe fica 'desligado' (do add column acima); quem
-- a põe em sombra é a migration de dado 20261026101000, com OK nomeado.
alter table public.agenda_config alter column modo_diaria set default 'sombra';

comment on column public.agenda_config.modo_equipe is
  'desligado = nada à equipe; sombra = grava a mensagem que mandaria (agenda_equipe_mensagens estado registrada) e lê as respostas sem efeito; ligado = manda a ficha, a confirmação e o ''como foi hoje?'', responde ''o que tem pra amanhã'', remaneja por ''não vou''/silêncio e a R10 deixa de mandar.';
comment on column public.agenda_config.modo_diaria is
  'desligado = a agenda não lança diária; sombra (nasce) = registra a diária que lançaria (agenda_acoes executada=false); ligado = lança quando a confirmação e o plano batem, e pergunta o resto.';
comment on column public.agenda_config.equipe_janela_inicio is 'Equipe: a 1ª hora em que o sistema manda mensagem (seg a sáb; nunca domingo). A janela entra no scheduled_for e no max_attempts da fila: o worker não confere janela.';
comment on column public.agenda_config.equipe_janela_fim is 'Equipe: nenhuma mensagem do sistema sai desta hora em diante (as horas da rotina ficam antes dela).';
comment on column public.agenda_config.equipe_hora_ficha is 'A ficha da véspera (onde, hora, com quem, sem valores). Nos dias em que a confirmação da manhã saiu, a ficha de amanhã vai dentro do "como foi hoje?" e não há esta.';
comment on column public.agenda_config.equipe_hora_confirmar is 'A confirmação da manhã, só para quem não respondeu OK à ficha.';
comment on column public.agenda_config.equipe_silencio_ate is 'Sem resposta à confirmação até esta hora (e sem "cheguei"/"ok" antes), o gestor remaneja e avisa o dono.';
comment on column public.agenda_config.equipe_hora_como_foi is 'O "como foi hoje?" (inteira ou meia diária, e como anda a OS).';
comment on column public.agenda_config.equipe_proativas_dia_max is 'Mensagens que o SISTEMA começa, por técnico e por dia.';
comment on column public.agenda_config.equipe_respostas_dia_max is 'Respostas do sistema a perguntas do técnico, por dia.';
comment on column public.agenda_config.equipe_resposta_validade is 'Até quanto tempo depois de mandada uma mensagem o "ok" do técnico responde a ela (decide a última mandada).';
comment on column public.agenda_config.diaria_janela_dias is 'Até quantos dias corridos atrás a agenda lança a diária sozinha.';
comment on column public.agenda_config.entrega_aviso_du is 'OS concluída sem entrega há estes dias úteis vira pergunta (não crítica) ao dono.';
comment on column public.agenda_config.carona_por_os_dias is 'A pergunta que pega carona no turno da conversa: no máximo 1 por OS a cada estes dias.';
comment on column public.agenda_config.carteira_laranja_du is 'Carteira: a OS parada há estes dias úteis fica laranja.';
comment on column public.agenda_config.carteira_vermelho_du is 'Carteira: a OS parada há estes dias úteis fica vermelha.';
comment on column public.agenda_config.ppc_meta is 'PPC (dias de serviço cumpridos ÷ planejados, por OS e dia) da semana abaixo disto vira linha no fechamento.';

-- ── 2. A entrega (concluído ≠ entregue) ─────────────────────────────────────────────────────────────────
alter table public.service_orders add column if not exists delivered_at timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.service_orders'::regclass and conname = 'so_entrega_depois_da_conclusao') then
    alter table public.service_orders add constraint so_entrega_depois_da_conclusao
      check (delivered_at is null or check_out_at is not null);
  end if;
end
$$;

comment on column public.service_orders.delivered_at is
  'Agenda de Produção (Fase 3): quando o bem foi entregue ao cliente (concluído ≠ entregue). Escrito só pela porta (os_transicionar_status / os_registrar_marco, com agenda.porta): o gatilho trg_so_entrega_pela_porta recusa o resto. Só existe com check_out_at.';

-- ── 3. Alocação: a diária do meio-dia e a resposta da equipe ────────────────────────────────────────────
alter table public.agenda_alocacoes
  add column if not exists work_shift_id uuid references public.work_shifts(id) on delete set null;
create index if not exists agenda_alocacoes_turno on public.agenda_alocacoes(work_shift_id) where work_shift_id is not null;

alter table public.agenda_alocacoes drop constraint if exists agenda_alocacoes_resultado_via_check;
alter table public.agenda_alocacoes add constraint agenda_alocacoes_resultado_via_check
  check (resultado_via in ('dia_feito','conversa','tela','sistema','equipe'));

comment on column public.agenda_alocacoes.work_shift_id is
  'Agenda de Produção (Fase 3): a diária (work_shifts) lançada para este meio-dia. Apagar a diária deixa nulo (a alocação fica).';

-- ── 4. Ações: a pessoa, a diária e as cobranças; os tipos da execução ───────────────────────────────────
alter table public.agenda_acoes
  add column if not exists payee_id       uuid references public.payees(id) on delete set null,
  add column if not exists work_shift_id  uuid references public.work_shifts(id) on delete set null,
  add column if not exists receivable_ids uuid[] not null default '{}';

alter table public.agenda_acoes drop constraint if exists agenda_acoes_tipo_check;
alter table public.agenda_acoes add constraint agenda_acoes_tipo_check
  check (tipo in ('publicar','criar','mover','cancelar','fixar','promover_reserva','soltar_reserva','status','resultado',
                  'desfazer','diaria','concluir','entregar','equipe'));
alter table public.agenda_acoes drop constraint if exists agenda_acoes_origem_check;
alter table public.agenda_acoes add constraint agenda_acoes_origem_check
  check (origem in ('motor','vigia','conferencia','dono','assistente','tela','aprovacao','sistema','equipe'));

comment on column public.agenda_acoes.payee_id is 'Agenda de Produção (Fase 3): a pessoa da ação de equipe ou de diária.';
comment on column public.agenda_acoes.work_shift_id is 'Agenda de Produção (Fase 3): a diária que a ação lançou (tipo diaria). Apagar a diária deixa nulo (a ação fica).';
comment on column public.agenda_acoes.receivable_ids is 'Agenda de Produção (Fase 3): as cobranças que a conclusão criou (tipo concluir). O desfazer cancela só estas, e só se nada foi pago.';

-- ── 5. Perguntas: a pessoa, a carona e os tipos novos (a diária que diverge é crítica) ──────────────────
alter table public.agenda_perguntas
  add column if not exists payee_id  uuid references public.payees(id) on delete set null,
  add column if not exists carona_em timestamptz;

alter table public.agenda_perguntas drop constraint if exists agenda_perguntas_tipo_check;
alter table public.agenda_perguntas add constraint agenda_perguntas_tipo_check
  check (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono',
                  'conferencia','chegou','parada','estouro','duracao','material_conferir','padrao_do_dono',
                  'diaria','diaria_ligar','equipe_resposta','concluir','entrega'));

-- A coluna gerada: a diária que diverge passa a ser crítica. SET EXPRESSION (Postgres 17+) mantém a coluna no lugar e
-- reconstrói e revalida critica_tem_opcoes e critica_decidida com o mesmo nome. Só se a expressão ainda não tem 'diaria'
-- (rodar de novo não reescreve a tabela).
do $$
begin
  if exists (select 1
               from pg_attribute a
               join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
              where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica' and a.attgenerated = 's'
                and pg_get_expr(d.adbin, d.adrelid) not like '%''diaria''%') then
    if current_setting('server_version_num')::int < 170000 then
      raise exception 'agenda_perguntas.critica: esta migration precisa do Postgres 17 ou mais novo (ALTER COLUMN … SET EXPRESSION); este é o %.',
        current_setting('server_version');
    end if;
    alter table public.agenda_perguntas alter column critica set expression as
      (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono','diaria'));
  end if;
end
$$;

comment on column public.agenda_perguntas.payee_id is 'Agenda de Produção (Fase 3): a pessoa da pergunta (diaria, diaria_ligar, equipe_resposta).';
comment on column public.agenda_perguntas.carona_em is 'Agenda de Produção (Fase 3): quando a pergunta foi junto de uma resposta do assistente ao dono (carona). No máximo 1 por OS a cada carona_por_os_dias.';

-- O gatilho de antes da pergunta (Fase 2, corpo de 20261025100000:672-703), recriado.
create or replace function public._agenda_perguntas_antes()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  -- (opções que não são lista: quem recusa é o CHECK da coluna)
  if jsonb_typeof(new.opcoes) = 'array' and jsonb_array_length(new.opcoes) > 0 then
    if new.recomendacao is not null
       and not exists (select 1 from jsonb_array_elements(new.opcoes) e where e ->> 'n' = new.recomendacao::text) then
      raise exception 'A recomendação tem de ser uma das opções da pergunta.';
    end if;
    if new.opcao_escolhida is not null
       and not exists (select 1 from jsonb_array_elements(new.opcoes) e where e ->> 'n' = new.opcao_escolhida::text) then
      raise exception 'Essa opção não existe nesta pergunta.';
    end if;
  end if;
  if tg_op = 'UPDATE'
     and not public._agenda_so_mudou(to_jsonb(old) - 'critica', to_jsonb(new) - 'critica',
           case when old.estado = 'aberta'
                -- FASE 3: carona_em (a pergunta que foi junto de uma resposta) muda como o "mostrada".
                then array['estado', 'mostrada_vezes', 'mostrada_em', 'mostrada_via', 'respondida_em', 'respondida_por',
                           'respondida_via', 'opcao_escolhida', 'resposta', 'resolvida_motivo', 'expira_em', 'carona_em']
                else '{}'::text[] end,
           -- FASE 3: payee_id é ON DELETE SET NULL (apagar o favorecido deixa a pergunta com a pessoa nula).
           array['service_order_id', 'os_material_id', 'proposta_id', 'respondida_por', 'payee_id']) then
    if old.estado = 'aberta' then
      raise exception 'A pergunta não muda o que pergunta: só se mostra, se responde ou se resolve.';
    end if;
    raise exception 'A pergunta fechada não muda: a decisão registrada fica como foi.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_perguntas_antes() is 'Agenda de Produção (Fase 2; Fase 3: carona_em e payee_id): gatilho BEFORE INSERT/UPDATE — recomendação e opção escolhida são uma das opções; a pergunta só sai de aberta, com o que a mostra/responde/resolve (e a carona); fechada não muda.';

-- ── 6. Rodadas: a vigia e a rotina da equipe na mesma tabela ────────────────────────────────────────────
alter table public.agenda_vigia_rodadas
  add column if not exists rotina      text not null default 'vigia',
  add column if not exists modo_equipe text,
  add column if not exists modo_diaria text;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_vigia_rodadas_rotina_check',      'check (rotina in (''vigia'', ''rotina''))'),
      ('agenda_vigia_rodadas_modo_equipe_check', 'check (modo_equipe is null or modo_equipe in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_vigia_rodadas_modo_diaria_check', 'check (modo_diaria is null or modo_diaria in (''desligado'', ''sombra'', ''ligado''))')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_vigia_rodadas'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_vigia_rodadas add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.agenda_vigia_rodadas.rotina is 'Agenda de Produção (Fase 3): vigia (o tique da Fase 2) ou rotina (a rotina da equipe e da diária). As rodadas de antes são da vigia.';
comment on column public.agenda_vigia_rodadas.modo_equipe is 'Agenda de Produção (Fase 3): o modo_equipe no instante do tique (nulo nas rodadas da Fase 2).';
comment on column public.agenda_vigia_rodadas.modo_diaria is 'Agenda de Produção (Fase 3): o modo_diaria no instante do tique (nulo nas rodadas da Fase 2).';

-- ── 7. As quatro tabelas ────────────────────────────────────────────────────────────────────────────────

-- (1) Quem recebe a rotina da equipe. Ninguém entra por cadastro: só a semente (regra) ou o dono.
create table if not exists public.agenda_equipe_contato (
  payee_id      uuid primary key references public.payees(id) on delete cascade,
  recebe_rotina boolean not null default false,
  incluido_por  text not null check (incluido_por in ('regra','dono')),
  incluido_em   timestamptz not null default now(),
  parou_em      timestamptz,
  parou_motivo  text check (char_length(parou_motivo) <= 200),
  constraint parou_coerente check ((parou_em is null) or not recebe_rotina)
);

comment on table public.agenda_equipe_contato is
  'Agenda de Produção (Fase 3): quem recebe a rotina da equipe (ficha, confirmação, "como foi hoje?"). Lista explícita: entra pela semente (regra da d14: diarista com perfil vigente, telefone e diária recente) ou pelo dono, nunca por cadastro. Parar ("para de mandar", do técnico ou do dono) guarda quando e por quê.';
comment on column public.agenda_equipe_contato.parou_em is '"Para de mandar" do técnico ou do dono. Com parou_em, recebe_rotina é false.';

-- (2) Toda mensagem à equipe (mandada ou só registrada em sombra) e a resposta. NUNCA apagada.
create table if not exists public.agenda_equipe_mensagens (
  id             uuid primary key default gen_random_uuid(),
  payee_id       uuid not null references public.payees(id),
  dia            date not null,
  tipo           text not null check (tipo in ('ficha','confirmar','como_foi','resposta')),
  leva_ficha_de  date,
  modo           text not null check (modo in ('sombra','ligado')),
  texto          text not null check (char_length(texto) between 3 and 600),
  enviar_em      timestamptz not null,
  estado         text not null default 'registrada' check (estado in
                   ('registrada','enfileirada','respondida','sem_resposta','recusada')),
  recusa_motivo  text check (recusa_motivo in ('teto','janela','domingo','sem_telefone','sem_plano','parou','modo')),
  fila_id        uuid,
  dedupe_key     text not null unique,
  responde_wa_id text,
  resposta_texto text check (char_length(resposta_texto) <= 500),
  resposta_em    timestamptz,
  resposta_wa_id text,
  leitura        jsonb check (leitura is null or jsonb_typeof(leitura) = 'object'),
  acao_id        uuid references public.agenda_acoes(id) on delete set null,
  criada_em      timestamptz not null default now(),
  constraint recusa_coerente   check ((estado = 'recusada') = (recusa_motivo is not null)),
  constraint resposta_coerente check ((resposta_em is null) = (resposta_texto is null))
);

create unique index if not exists agenda_equipe_uma_por_dia on public.agenda_equipe_mensagens(payee_id, dia, tipo, modo)
  where tipo <> 'resposta';
create index if not exists agenda_equipe_por_envio on public.agenda_equipe_mensagens(payee_id, enviar_em desc);

comment on table public.agenda_equipe_mensagens is
  'Agenda de Produção (Fase 3): toda mensagem à equipe — a ficha da véspera, a confirmação da manhã, o "como foi hoje?" e a resposta a uma pergunta dele —, mandada (ligado) ou só registrada (sombra), recusada com o motivo (teto, janela, domingo, sem telefone, sem plano, parou, modo), e a resposta dele com a leitura sem IA. Uma por pessoa, dia, tipo e modo (fora as respostas). NUNCA apagada; só o estado, a fila, a resposta, a leitura e a ação mudam.';
comment on column public.agenda_equipe_mensagens.dia is 'O dia de que a mensagem fala (a ficha de amanhã tem o dia de amanhã).';
comment on column public.agenda_equipe_mensagens.leva_ficha_de is 'O "como foi hoje?" que leva a ficha de amanhã (nos dias em que a confirmação da manhã saiu, não há a das 19:30).';
comment on column public.agenda_equipe_mensagens.fila_id is 'whatsapp_send_queue.id quando enfileirada (sem FK: a fila é podada).';
comment on column public.agenda_equipe_mensagens.dedupe_key is 'agenda-equipe:<tipo>:<payee>:<dia>[:<n>] — a chave da fila (whatsapp_send_queue.dedupe_key). Em sombra a chave termina em ":sombra": a mesma mensagem pode existir nos dois modos (agenda_equipe_uma_por_dia inclui o modo) e a de verdade não pode colidir com a registrada.';
comment on column public.agenda_equipe_mensagens.responde_wa_id is 'Tipo resposta: a mensagem dele que ela responde.';
comment on column public.agenda_equipe_mensagens.leitura is 'O que a gramática fixa leu da resposta (presença, jornada, terminou, não vou, não entendida…).';

-- (3) O dono foi sem estar previsto (ou ficou mais do que o previsto): o insumo do aprendizado da presença (Fase 6).
create table if not exists public.agenda_intervencoes_do_dono (
  id               uuid primary key default gen_random_uuid(),
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  dia              date not null,
  prevista         text not null check (prevista in ('nenhuma','abertura','fechamento','abre_e_fecha','turno')),
  dita             text not null check (dita in ('manha','tarde','dia','passou')),
  classe           text not null check (classe in ('diagnostico','comissionamento','marina_nova','execucao')),
  origem           text not null check (origem in ('conversa','conferencia','tela')),
  trecho           text check (char_length(trecho) <= 300),
  autor            uuid references public.app_users(id) on delete set null,
  criado_em        timestamptz not null default now(),
  unique (service_order_id, dia, origem)
);

comment on table public.agenda_intervencoes_do_dono is
  'Agenda de Produção (Fase 3): o dono foi a uma OS sem estar no plano (ou ficou mais do que o previsto) — o que estava previsto, o que ele disse, a classe da OS e de onde veio. Uma por OS, dia e origem. É o insumo do aprendizado da presença (Fase 6) das OS parecidas.';

-- (4) Comissão "o maior dos dois": os parâmetros. O pagamento é DESLIGADO por construção (só muda com o OK do dono,
-- noutra fase, numa migration que troque este CHECK).
create table if not exists public.comissao_config (
  id            boolean primary key default true check (id),
  pct           numeric(4,3) not null default 0.200 check (pct between 0 and 0.5),
  modelo        text not null default 'maior_dos_dois' check (modelo in ('maior_dos_dois')),
  inicio        date,
  meses_teste   smallint not null default 3 check (meses_teste between 1 and 12),
  imposto_fonte text not null default 'aliquota_simples_com_nota' check (imposto_fonte in ('aliquota_simples_com_nota','nenhum')),
  pagamento     text not null default 'desligado' check (pagamento = 'desligado')
);

insert into public.comissao_config default values on conflict do nothing;

comment on table public.comissao_config is
  'Comissão dos técnicos "o maior dos dois" (decisões de 23/10): a diária é o piso; por mês, pct do lucro líquido das OS concluídas E pagas, dividido pelos dias trabalhados nelas; o que passar das diárias seria bônus. Só a conta e o resumo: o pagamento é desligado por construção (CHECK pagamento = desligado). Uma linha só (id = true).';
comment on column public.comissao_config.inicio is 'O 1º mês do teste (meses_teste). Nulo = o dono ainda não disse.';
comment on column public.comissao_config.imposto_fonte is 'aliquota_simples_com_nota = a alíquota do Simples (company_fiscal_settings.nfse_total_tax_rate_sn, senão app_settings.simples_aliquota) × o recebido, só com nota autorizada ligada à OS; nenhum = sem imposto na conta.';
comment on column public.comissao_config.pagamento is 'Sempre desligado nesta fase: nada grava em commissions nem em payables.';

-- As mensagens nunca se apagam e só o estado, a fila, a resposta, a leitura e a ação mudam.
create or replace function public._agenda_equipe_mensagens_so_responde()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new),
           array['estado', 'recusa_motivo', 'fila_id', 'resposta_texto', 'resposta_em', 'resposta_wa_id', 'leitura', 'acao_id'],
           array['acao_id']) then
    raise exception 'A mensagem registrada não muda: só o estado, a fila e a resposta.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_equipe_mensagens_so_responde() is
  'Agenda de Produção (Fase 3): gatilho BEFORE UPDATE de agenda_equipe_mensagens — só estado, recusa_motivo, fila_id, resposta_*, leitura e acao_id mudam; o texto, a pessoa, o dia e o modo ficam como foram.';

drop trigger if exists agenda_equipe_mensagens_nao_apaga on public.agenda_equipe_mensagens;
create trigger agenda_equipe_mensagens_nao_apaga before delete on public.agenda_equipe_mensagens
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_equipe_mensagens_so_responde on public.agenda_equipe_mensagens;
create trigger agenda_equipe_mensagens_so_responde before update on public.agenda_equipe_mensagens
  for each row execute function public._agenda_equipe_mensagens_so_responde();

-- ── 8. A ação registrada: as FKs novas que viram nulas (Fase 2, corpo de 20261025100000:706-721) ─────────
create or replace function public._agenda_acoes_so_desfaz()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new),
           case when old.desfeita_em is null
                then array['desfeita_em', 'desfeita_por', 'desfeita_pela', 'contada_em', 'contada_via']
                else array['contada_em', 'contada_via'] end,
           -- FASE 3: payee_id e work_shift_id são ON DELETE SET NULL (apagar a diária no Financeiro deixa a ação com a
           -- diária nula; o registro fica).
           array['service_order_id', 'proposta_id', 'autor', 'desfeita_por', 'payee_id', 'work_shift_id']) then
    raise exception 'A ação registrada não muda: só se desfaz (uma vez) ou se marca como contada.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_acoes_so_desfaz() is 'Agenda de Produção (Fase 2; Fase 3: payee_id e work_shift_id podem virar nulos pelo ON DELETE SET NULL): gatilho BEFORE UPDATE — só desfeita_* (uma vez) e contada_* mudam.';

-- ── 9. O gatilho da entrega ─────────────────────────────────────────────────────────────────────────────
-- A entrega só pela porta, em todos os modos: a coluna é nova e ninguém mais escreve nela. Valor igual passa (o
-- formulário que manda a linha inteira não tropeça). Também a OS que NASCE entregue (uma cópia da linha inteira de
-- outra OS) é recusada: a spec pedia só o UPDATE, e o INSERT deixaria a entrega entrar sem a porta. security definer
-- como _so_datas_pela_agenda (Fase 2).
create or replace function public._so_entrega_pela_porta()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if (case when tg_op = 'INSERT' then new.delivered_at is not null
           else new.delivered_at is distinct from old.delivered_at end)
     and coalesce(current_setting('agenda.porta', true), '') <> 'on' then
    raise exception 'A entrega é registrada na OS (botão Entregue) ou dizendo "entreguei <cliente>".';
  end if;
  return new;
end;
$function$;

comment on function public._so_entrega_pela_porta() is
  'Agenda de Produção (Fase 3): gatilho BEFORE INSERT e BEFORE UPDATE OF delivered_at em service_orders — fora da porta (agenda.porta = on, ligada só pelas funções security definer da porta) recusa escrever a entrega, em todos os modos. Valor igual passa; OS nova sem entrega passa.';

drop trigger if exists trg_so_entrega_pela_porta on public.service_orders;
create trigger trg_so_entrega_pela_porta before insert or update of delivered_at on public.service_orders
  for each row execute function public._so_entrega_pela_porta();

-- ── 10. Portas: RLS, só leitura, escrita só pelas RPCs ──────────────────────────────────────────────────
alter table public.agenda_equipe_contato       enable row level security;
alter table public.agenda_equipe_mensagens     enable row level security;
alter table public.agenda_intervencoes_do_dono enable row level security;
alter table public.comissao_config             enable row level security;

drop policy if exists agenda_equipe_contato_leitura on public.agenda_equipe_contato;
create policy agenda_equipe_contato_leitura on public.agenda_equipe_contato
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists agenda_equipe_mensagens_leitura on public.agenda_equipe_mensagens;
create policy agenda_equipe_mensagens_leitura on public.agenda_equipe_mensagens
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists agenda_intervencoes_do_dono_leitura on public.agenda_intervencoes_do_dono;
create policy agenda_intervencoes_do_dono_leitura on public.agenda_intervencoes_do_dono
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists comissao_config_leitura on public.comissao_config;
create policy comissao_config_leitura on public.comissao_config
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.agenda_equipe_contato, public.agenda_equipe_mensagens, public.agenda_intervencoes_do_dono,
  public.comissao_config from public, anon, authenticated;
grant select on table public.agenda_equipe_contato, public.agenda_equipe_mensagens, public.agenda_intervencoes_do_dono,
  public.comissao_config to authenticated;
grant all on table public.agenda_equipe_contato, public.agenda_equipe_mensagens, public.agenda_intervencoes_do_dono,
  public.comissao_config to service_role;

-- Funções de gatilho: sem grant a ninguém (as recriadas também: create or replace mantém a ACL da Fase 2, e o revoke
-- de novo não custa).
revoke all on function public._agenda_equipe_mensagens_so_responde(), public._so_entrega_pela_porta(),
  public._agenda_perguntas_antes(), public._agenda_acoes_so_desfaz()
  from public, anon, authenticated;
