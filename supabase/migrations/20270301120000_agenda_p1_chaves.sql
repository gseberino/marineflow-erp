-- Agenda de Produção — pacote 1 do assistente (24/11/2026): as 4 chaves novas de agenda_config.
--
-- Por quê: cada mudança do pacote 1 na agenda nasce atrás de uma chave, e as quatro entram juntas para a tabela ser alterada uma vez só
-- (especificação: D:/IA-HBR/Trabalho/avaliacao-assistente-20261124/pacote1/spec-agenda.md, seção 7).
--
-- O que muda: só 4 colunas em agenda_config, cada uma com o valor que mantém o comportamento de antes, menos equipe_terminei_conclui:
--   · equipe_silencio_acao     (A2)  'tirar' = o silêncio das 9h tira o dia (de antes); 'manter' = mantém o dia, avisa o dono e pede de novo.
--   · equipe_terminei_conclui  (A3)  false = o "terminei"/"ok" do último dia vira a pergunta "terminou ou falta dia?" ao dono (nasce assim:
--                                    conserto de segurança, só tira autonomia); true = conclui a OS em nome da equipe (de antes).
--   · sinal_cobrar_max_dias    (A1b) null = sem limite (de antes); N = orçamento esperando o sinal há mais de N dias não ganha dia sozinho.
--   · manha_sobras_max         (A5/A4) 0 = nenhuma (de antes); até 3 perguntas que sobraram do fechamento vão na manhã das 07:30.
-- Nenhuma função lê as colunas nesta migration: quem as lê é recriado nas migrations seguintes da faixa 20270301120100–20270301120400.
-- _agenda_cfg() devolve a linha inteira (agenda_config%rowtype): as colunas novas chegam sozinhas às funções.
--
-- Ao aplicar: ADD COLUMN com DEFAULT constante não reescreve a tabela, mas pede ACCESS EXCLUSIVE por milissegundos em agenda_config, que toda
-- função da agenda lê a cada tique: aplicar FORA dos minutos :00, :15, :30 e :45 e fora de 17:25–17:55 (o fechamento).
--
-- IDEMPOTENTE: add column if not exists (o CHECK da coluna vai junto e só entra quando a coluna entra).
-- DESFAZER (depois de reverter as funções que as leem): alter table public.agenda_config drop column equipe_silencio_acao,
-- drop column equipe_terminei_conclui, drop column sinal_cobrar_max_dias, drop column manha_sobras_max.

alter table public.agenda_config
  add column if not exists equipe_silencio_acao text not null default 'tirar'
      check (equipe_silencio_acao in ('tirar', 'manter')),
  add column if not exists equipe_terminei_conclui boolean not null default false,
  add column if not exists sinal_cobrar_max_dias integer check (sinal_cobrar_max_dias between 1 and 120),
  add column if not exists manha_sobras_max smallint not null default 0 check (manha_sobras_max between 0 and 3);

comment on column public.agenda_config.equipe_silencio_acao is 'Pacote 1, A2 (decisão do dono de 24/11/2026): tirar = o silêncio das 9h tira o dia (de antes); manter = mantém o dia, avisa o dono e pede de novo ao técnico.';
comment on column public.agenda_config.equipe_terminei_conclui is 'Pacote 1, A3: false = o "terminei"/"ok" do último dia vira a pergunta "terminou ou falta dia?" ao dono; true = conclui a OS em nome da equipe (de antes).';
comment on column public.agenda_config.sinal_cobrar_max_dias is 'Pacote 1, A1b (AG7-09 com idade): orçamento em aguardando sinal há mais de N dias não ganha dia sozinho; null = sem limite (de antes).';
comment on column public.agenda_config.manha_sobras_max is 'Pacote 1, A5/A4: quantas perguntas da agenda que sobraram (e a conferência de ontem) vão na manhã das 07:30; 0 = nenhuma (de antes).';

insert into supabase_migrations.schema_migrations (version, name) values ('20270301120000','agenda_p1_chaves');
