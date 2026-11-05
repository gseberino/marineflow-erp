-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), pacote P1: a base — os 6 interruptores e os 25
-- parâmetros da etapa, as 14 colunas do local e do bem no planejamento da OS, o cadastro dos locais (agenda_locais) e o registro de
-- quem está autorizado (os_autorizados), as listas fechadas ampliadas, as duas expressões geradas (critica e modelo), a regra de
-- "conferido", o modo com o freio (_agenda_local_modo) e o modo cru das 3 perguntas novas (_agenda_modo_da_pergunta recriada).
-- Spec: scratchpad agenda-pesquisa/spec-fase7d.md (§4, §5.1, §8.3 agenda_fase7d_base.sql e o bloco R6: R6.2, R6.3-1, R6.4, R6.7a item 1,
-- R6.7b, R6.10); nomes: fase7-registro.md §1 (7d P1); respostas do dono: fase7-padroes.md (AG7-14 o acesso é preparo, nunca filtro de
-- pessoa; AG7-18 um local só: o espaço da HBR dentro do pátio da MP Motorhomes; AG7-19 a região e a viagem; AG7-20 a temporada; AG7-21 o
-- M11 aprovado; AG7-01 ligar direto, com o OK nomeado).
-- Depende das Fases 1 a 6, do lote de 30/10, da 7a inteira (o ampliador de listas, o validador de regex, gestor_so_propor), da 7b
-- inteira e da 7c inteira (20261102100000 .. 100590; a recriada vem de 20261102100550).
--
-- ═══ DDL — OK NOMEADO ═══ (31 colunas novas em agenda_config — 6 interruptores, 24 parâmetros e onde_fica_desde — e o DEFAULT dos 6
-- interruptores; 14 colunas novas em os_planejamento, todas nulas; 2 tabelas novas com 1 índice único, 3 gatilhos e a RLS de leitura; 5
-- listas fechadas pelo ampliador e 1 à mão; 2 colunas geradas por SET EXPRESSION; 34 CHECKs novos por nome; 3 funções novas (1 de
-- gatilho) e 1 recriada; nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7d/p1/montar-migration.mjs: a
-- recriada é o corpo da definição MAIS NOVA (conferida a cada montagem: o montador para se outra migration a definir depois da origem),
-- _agenda_modo_da_pergunta de 20261102100550_agenda_fase7c_tarefas.sql, e a mudança está só no bloco "-- FASE 7d: … -- FASE 7d: fim".
-- Tirado o bloco, o corpo é o da origem, byte a byte (o montador e o B6 de supabase/tests/agenda_fase7d_base.sql conferem).
--
-- POR QUE: a agenda escala hoje sem saber ONDE o serviço acontece: não sabe que um local fecha num dia, que um motorhome ocupa vaga no
-- pátio, que uma OS em outra cidade gasta meio-dia de estrada, nem se o barco está na água ou em seco. Esta migration só cria o lugar e
-- as regras; quem muda alguma coisa são as próximas (20261107100100 a 100700), sempre atrás dos interruptores. Com os 6 desligados (a
-- linha nasce assim), nada muda para ninguém.
--
-- O QUE MUDA:
--   1. agenda_config: os interruptores modo_local_calendario, modo_local_autorizacao (o PREPARO do acesso: nunca filtro de pessoa),
--      modo_bem, modo_patio, modo_viagem e modo_mesmo_local — desligado | sombra | ligado; a linha fica 'desligado', o DEFAULT da coluna
--      vira 'sombra' (como na 7a, na 7b e na 7c); quem os põe em sombra é a migration de dado 20261107100900, com OK nomeado. E os
--      parâmetros: a validade da regra conferida (365 dias), o acesso até D-2 e a decisão urgente em D-1, a reserva da marina, a garagem
--      seca, a tolerância do horário, a entrada e a retirada do pátio, os meses de temporada (a fonte ÚNICA: o 7e lê daqui), a viagem
--      (UF da ida e volta, deslocamento regional e de ida e volta, fator de estrada, km/h, meios de estrada, km cobrado), a janela da
--      pergunta "onde fica", a hora da rodada (16:15) e as palavras do estado do bem. CHECK por nome em cada um.
--      onde_fica_desde (nula): a data a partir da qual uma OS aprovada pode receber o M11; nula = ninguém (R6.7a). Quem a grava é o dado.
--   2. agenda_locais (nova): o cadastro dos locais, ligado a marinas por marina_id. Não vai em marinas porque qualquer usuário logado
--      escreve lá; uma regra dura não pode morar numa tabela que o técnico edita. Regra só vale como regra com conferido_por dono ou
--      marina e dentro de local_conferencia_validade_dias; a pesquisa é nota (AG7-14). Um só patio_hbr ativo (AG7-18). Não se apaga.
--   3. os_autorizados (nova): quem está autorizado no local da OS. É DADO do preparo do acesso, nunca filtro de pessoa (AG7-14). Sai por
--      revogado_em; não se apaga.
--   4. os_planejamento: o local dito e de quem veio (local_id, local_fonte, local_em), o estado do bem (bem_situacao e a fonte,
--      bem_exige, descer_quem), a entrada e a retirada do motorhome (entrada_em, retirada_em, entrada_fonte), a viagem dita e os fatos
--      combinados (reserva_marina_ok_em, descida_ok_em). Nada escreve aqui ainda.
--   5. As listas fechadas: agenda_perguntas.tipo + local, combinar, acesso; agenda_acoes.tipo + local; agenda_vigia_rodadas.rotina +
--      local; agenda_alocacoes.cancelada_motivo + local; agenda_cliente_mensagens.tipo + onde_fica (pelo ampliador da 7a).
--      agenda_config_cliente_tipos_ligados_check + onde_fica, À MÃO: o CHECK é "<@", e o ampliador só aceita "= ANY" (R6.4). O valor de
--      produção continua com os 11: o tipo novo fica FORA da lista, ou seja, em teste.
--   6. As colunas geradas, por SET EXPRESSION (Postgres 17+), copiando a expressão de hoje e somando só o novo: critica + acesso (só
--      esse: local e combinar não são críticas); modelo + 'onde_fica' = M11 (sem isso cairia no else M10).
--   7. _agenda_local_conferido (nova): a regra do "conferido" (§3.1, item 8). _agenda_local_modo (nova, molde de _agenda_gestor_modo): o
--      modo EFETIVO de calendario, acesso, bem, patio, viagem e mesmo_local; ligado + *gestor, só propor* = sombra (R6.7b). Todo leitor de
--      modo da 7d usa ela, nunca cf.modo_x.
--   8. _agenda_modo_da_pergunta (de 20261102100550): local = modo_cliente; acesso = modo_local_autorizacao; combinar pela chave
--      (combinar:reserva_marina:… e combinar:descida:… = modo_bem; combinar:entrada:… = modo_patio; o resto, combinar:acesso:… incluído,
--      = modo_local_autorizacao). É o modo CRU, sem o freio: a pergunta já aberta continua respondível com *gestor, só propor* (R6.7b).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7d_base.sql; registradas em notas-fase7d.md, P1):
--   · agenda_locais.historico: o CHECK em CASE (o molde de agenda_alocacoes.historico), não "tipo = array AND tamanho <= 20": com o AND, um
--     valor que não é lista daria erro de jsonb_array_length em vez da recusa do CHECK;
--   · as "4 antecedências 0..10" da §4.1 são 3 colunas (autorizacao_antecedencia_du, marina_reserva_antecedencia_du,
--     patio_entrada_antecedencia_du); a 4ª da conta antiga, acesso_urgente_du, tem o limite próprio do bloco R: 0..autorizacao_antecedencia_du;
--   · combinar com chave que não é de nenhum dos 4 tipos cai em modo_local_autorizacao (o molde do tipo habilidade), não em nulo: os testes
--     "todo tipo da lista fechada tem o modo" (S4, B6c, B11b) reprovam tipo com modo nulo.
--
-- O QUE NÃO MUDA: com os 6 interruptores desligados, o motor, a vigia, os textos à equipe e ao cliente e as Fases 1 a 7c, byte a byte
-- (nada de antes chama as funções novas). Os valores de antes continuam nas listas; as críticas de antes continuam as mesmas; o modelo dos
-- 11 tipos de antes é o mesmo; o modo de todo tipo de pergunta de antes é o mesmo.
--
-- ORDEM DE LIGAR (spec R6.11): depois da 7c inteira; antes de 20261107100100 (P2), que lê as colunas novas. À noite, depois das 21:00,
-- logo depois de um tique, com LOCK_TIMEOUT=5s: os SET EXPRESSION reescrevem agenda_perguntas e agenda_cliente_mensagens. Aplicar sozinha
-- não muda nada para ninguém (os interruptores ficam 'desligado' na linha).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7d_base.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261107100000
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261107100000_agenda_fase7d_tabelas.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261107100000', 'agenda_fase7d_tabelas');"
--
-- DESFAZER (só a estrutura; nada usa as colunas antes das próximas migrations): recriar _agenda_modo_da_pergunta com o corpo de
-- 20261102100550; o resto pode ficar (colunas nulas ou com DEFAULT, listas só somadas, as tabelas vazias). Para tirar mesmo (só sem linha
-- nas tabelas novas e sem valor novo nas listas):
--   alter table public.os_planejamento drop column if exists local_id, drop column if exists local_fonte, drop column if exists local_em,
--     drop column if exists bem_situacao, drop column if exists bem_situacao_fonte, drop column if exists bem_situacao_em,
--     drop column if exists bem_exige, drop column if exists descer_quem, drop column if exists entrada_em,
--     drop column if exists retirada_em, drop column if exists entrada_fonte, drop column if exists viagem,
--     drop column if exists reserva_marina_ok_em, drop column if exists descida_ok_em;
--   drop table if exists public.os_autorizados;
--   drop table if exists public.agenda_locais;
--   drop function if exists public._agenda_local_modo(text), public._agenda_local_conferido(uuid, date), public._agenda_locais_historico();
--   (agenda_config: drop dos 30 CHECKs e das 31 colunas; critica e modelo: SET EXPRESSION com a expressão de antes; as listas: recriar o
--    CHECK de cada uma com os valores da 7c)
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$ (só cria o que falta), as listas pelo ampliador (soma só o que falta), a
-- lista à mão e os SET EXPRESSION só quando ainda não têm o valor novo, create table/index if not exists, create or replace function, drop
-- trigger/policy if exists + create, revoke/grant e comment.

-- ── 1. agenda_config: os interruptores e os parâmetros ──────────────────────────────────────────────
alter table public.agenda_config
  -- a linha fica 'desligado' até a migration de dado 20261107100900 (o molde da 7a, da 7b e da 7c); o DEFAULT passa a 'sombra' abaixo
  add column if not exists modo_local_calendario           text         not null default 'desligado',  -- AG7-14
  add column if not exists modo_local_autorizacao          text         not null default 'desligado',  -- AG7-14
  add column if not exists modo_bem                        text         not null default 'desligado',  -- AG7-14 (garagem seca, descida), AG7-20
  add column if not exists modo_patio                      text         not null default 'desligado',  -- AG7-18
  add column if not exists modo_viagem                     text         not null default 'desligado',  -- AG7-19
  add column if not exists modo_mesmo_local                text         not null default 'desligado',  -- AG7-20
  add column if not exists local_conferencia_validade_dias smallint     not null default 365,  -- AG7-14: regra conferida vale 1 ano
  add column if not exists autorizacao_antecedencia_du     smallint     not null default 2,    -- AG7-14 ([R] o acesso combinado até D-2)
  add column if not exists acesso_urgente_du               smallint     not null default 1,    -- AG7-14 ([R] sem acesso em D-1 = decisão urgente)
  add column if not exists marina_reserva_antecedencia_du  smallint     not null default 2,    -- AG7-14 (Jangadeiros pede 48 h)
  add column if not exists garagem_reserva_min_meios       smallint     not null default 1,    -- AG7-14 (60 min no box: 1 meio-dia já pede)
  add column if not exists horario_tolerancia_min          smallint     not null default 30,   -- AG7-14
  add column if not exists patio_entrada_antecedencia_du   smallint     not null default 2,    -- AG7-18
  add column if not exists patio_retirada_du               smallint     not null default 1,    -- AG7-18: o bem sai no d.u. seguinte ao fim
  add column if not exists patio_tentativas                smallint     not null default 3,    -- estrutural (o encaixe tenta depois do dia cheio)
  add column if not exists temporada_meses                 smallint[]   not null default '{11,12,1,2,3}',  -- AG7-20
  add column if not exists viagem_uf_bate_volta            text[]       not null default '{SC}',           -- AG7-19
  add column if not exists deslocamento_regional_max_min   smallint     not null default 45,   -- AG7-19
  add column if not exists deslocamento_bate_volta_max_min smallint     not null default 120,  -- AG7-19
  add column if not exists deslocamento_fator_estrada      numeric(3,2) not null default 1.30, -- AG7-19
  add column if not exists deslocamento_kmh                smallint     not null default 60,   -- AG7-19
  add column if not exists bate_volta_meios_dia            smallint     not null default 1,    -- AG7-19
  add column if not exists pernoite_ida_meios              smallint     not null default 1,    -- AG7-19
  add column if not exists viagem_km_bate_volta            smallint     not null default 120,  -- AG7-19 (reserva: km cobrado da OS)
  add column if not exists viagem_km_pernoite              smallint     not null default 300,  -- AG7-19
  add column if not exists onde_fica_janela_dias           smallint     not null default 14,   -- AG7-21: aprovada há até N dias
  add column if not exists onde_fica_antes_dias            smallint     not null default 21,   -- AG7-21: ou com 1º dia em até N dias corridos
  add column if not exists onde_fica_desde                 date,                               -- AG7-21: nula = ninguém (R6.7a); o dado 100900 grava
  add column if not exists local_hora                      time         not null default '16:15', -- estrutural: depois do aprender (16:00), antes da publicação (16:30)
  add column if not exists bem_agua_palavras               text         not null
    default 'teste de mar|prova de mar|teste no mar|navegando|navegacao|motor ligado|sea trial',  -- AG7-14 (fase do teste)
  add column if not exists bem_seco_palavras               text         not null
    default 'casco|anodo|transdutor de casco|passa casco|fundo do barco|helice|eixo|pe de galinha';  -- AG7-14

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_modo_local_calendario_check',  'check (modo_local_calendario in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_local_autorizacao_check', 'check (modo_local_autorizacao in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_bem_check',               'check (modo_bem in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_patio_check',             'check (modo_patio in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_viagem_check',            'check (modo_viagem in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_mesmo_local_check',       'check (modo_mesmo_local in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_local_conferencia_validade_dias_check', 'check (local_conferencia_validade_dias between 30 and 730)'),
      ('agenda_config_autorizacao_antecedencia_du_check',     'check (autorizacao_antecedencia_du between 0 and 10)'),
      ('agenda_config_acesso_urgente_du_check',
       'check (acesso_urgente_du >= 0 and acesso_urgente_du <= autorizacao_antecedencia_du)'),
      ('agenda_config_marina_reserva_antecedencia_du_check',  'check (marina_reserva_antecedencia_du between 0 and 10)'),
      ('agenda_config_garagem_reserva_min_meios_check',       'check (garagem_reserva_min_meios between 1 and 10)'),
      ('agenda_config_horario_tolerancia_min_check',          'check (horario_tolerancia_min between 0 and 120)'),
      ('agenda_config_patio_entrada_antecedencia_du_check',   'check (patio_entrada_antecedencia_du between 0 and 10)'),
      ('agenda_config_patio_retirada_du_check',               'check (patio_retirada_du between 0 and 5)'),
      ('agenda_config_patio_tentativas_check',                'check (patio_tentativas between 1 and 6)'),
      ('agenda_config_temporada_meses_check',
       'check (cardinality(temporada_meses) > 0 and temporada_meses <@ ''{1,2,3,4,5,6,7,8,9,10,11,12}''::smallint[])'),
      -- a lista pode ser vazia (nenhuma UF de ida e volta: fora da região é sempre pernoite); nulo dentro dela, não
      ('agenda_config_viagem_uf_bate_volta_check',
       'check (array_position(viagem_uf_bate_volta, null::text) is null'
       || ' and array_to_string(viagem_uf_bate_volta, '','') ~ ''^([A-Z]{2}(,[A-Z]{2})*)?$'')'),
      ('agenda_config_deslocamento_regional_max_min_check',   'check (deslocamento_regional_max_min between 10 and 120)'),
      ('agenda_config_deslocamento_bate_volta_max_min_check',
       'check (deslocamento_bate_volta_max_min between 30 and 300 and deslocamento_bate_volta_max_min > deslocamento_regional_max_min)'),
      ('agenda_config_deslocamento_fator_estrada_check',      'check (deslocamento_fator_estrada between 1.00 and 2.00)'),
      ('agenda_config_deslocamento_kmh_check',                'check (deslocamento_kmh between 20 and 110)'),
      ('agenda_config_bate_volta_meios_dia_check',            'check (bate_volta_meios_dia between 0 and 1)'),
      ('agenda_config_pernoite_ida_meios_check',              'check (pernoite_ida_meios between 0 and 2)'),
      ('agenda_config_viagem_km_bate_volta_check',            'check (viagem_km_bate_volta between 20 and 999)'),
      ('agenda_config_viagem_km_pernoite_check',
       'check (viagem_km_pernoite between 50 and 2000 and viagem_km_pernoite > viagem_km_bate_volta)'),
      ('agenda_config_onde_fica_janela_dias_check',           'check (onde_fica_janela_dias between 1 and 60)'),
      ('agenda_config_onde_fica_antes_dias_check',            'check (onde_fica_antes_dias between 3 and 60)'),
      ('agenda_config_local_hora_check',
       'check (local_hora >= time ''12:00'' and local_hora <= hora_do_plano)'),
      ('agenda_config_bem_agua_palavras_check',
       'check (char_length(bem_agua_palavras) between 3 and 400 and public._agenda_regex_valido(bem_agua_palavras))'),
      ('agenda_config_bem_seco_palavras_check',
       'check (char_length(bem_seco_palavras) between 3 and 400 and public._agenda_regex_valido(bem_seco_palavras))')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

-- Como a 7a, a 7b e a 7c: a estrutura não muda comportamento. A linha que já existe fica 'desligado' (do add column acima); quem a põe em
-- sombra é a migration de dado 20261107100900, com OK nomeado (AG7-01: ligar no mesmo dia do pós-deploy verde).
alter table public.agenda_config
  alter column modo_local_calendario  set default 'sombra',
  alter column modo_local_autorizacao set default 'sombra',
  alter column modo_bem               set default 'sombra',
  alter column modo_patio             set default 'sombra',
  alter column modo_viagem            set default 'sombra',
  alter column modo_mesmo_local       set default 'sombra';

comment on column public.agenda_config.modo_local_calendario is
  'Agenda de Produção (Fase 7d, AG7-14): o calendário do local — feriado do município, sábado e horário do local conferido, retirada do motorhome. desligado = nada; sombra = mostra "Em teste: eu não marcaria…", o motor ignora; ligado = a máscara entra no motor e na violação. Leia por _agenda_local_modo(''calendario''), nunca direto: ligado + *gestor, só propor* = sombra.';
comment on column public.agenda_config.modo_local_autorizacao is
  'Agenda de Produção (Fase 7d, AG7-14): o PREPARO do acesso (nunca filtro de pessoa) — toda OS em local de terceiro precisa do acesso combinado até D-2; sem ele em D-1, decisão urgente ao dono; a ficha avisa. desligado = nada; sombra = o "combinar" do acesso em teste; ligado = a pergunta combinar e a crítica acesso. Leia por _agenda_local_modo(''acesso'').';
comment on column public.agenda_config.modo_bem is
  'Agenda de Produção (Fase 7d, AG7-14/AG7-20): o estado do bem — o "combinar" da vaga na garagem seca e da descida para o teste na água, e a suposição gravada na OS sem água/seco dito. Leia por _agenda_local_modo(''bem'').';
comment on column public.agenda_config.modo_patio is
  'Agenda de Produção (Fase 7d, AG7-18): o pátio — vagas no motor, entrada e retirada do motorhome, "combinar" da entrada. Sem número de vagas, só conta. Leia por _agenda_local_modo(''patio'').';
comment on column public.agenda_config.modo_viagem is
  'Agenda de Produção (Fase 7d, AG7-19): a OS de viagem — meios de estrada, dias seguidos e a mesma equipe na pernoite, sem abre e fecha do dono fora da região. Leia por _agenda_local_modo(''viagem'').';
comment on column public.agenda_config.modo_mesmo_local is
  'Agenda de Produção (Fase 7d, AG7-20): o local real no desempate — a chave do local, OS do mesmo local juntas no dia, quem já está lá primeiro e a troca de cidade como custo na temporada. Fora de ligado, o motor usa a chave antiga, byte a byte. Leia por _agenda_local_modo(''mesmo_local'').';
comment on column public.agenda_config.local_conferencia_validade_dias is
  'Agenda de Produção (Fase 7d, AG7-14): por quantos dias a regra conferida pelo dono ou pela marina vale como regra (365). Depois vira nota de novo. 30..730.';
comment on column public.agenda_config.autorizacao_antecedencia_du is
  'Agenda de Produção (Fase 7d, AG7-14): o acesso ao local de terceiro combinado até N dias úteis antes do 1º dia no local (2 = até D-2). 0..10.';
comment on column public.agenda_config.acesso_urgente_du is
  'Agenda de Produção (Fase 7d, AG7-14): sem acesso a N dias úteis do 1º dia, vira decisão urgente ao dono (1 = D-1). 0..autorizacao_antecedencia_du.';
comment on column public.agenda_config.marina_reserva_antecedencia_du is
  'Agenda de Produção (Fase 7d, AG7-14): a vaga de serviço na garagem seca reservada até N dias úteis antes (2; a Jangadeiros pede 48 h). 0..10.';
comment on column public.agenda_config.garagem_reserva_min_meios is
  'Agenda de Produção (Fase 7d, AG7-14): a partir de quantos meios-dias planejados a OS em garagem seca pede a reserva da vaga (1). 1..10.';
comment on column public.agenda_config.horario_tolerancia_min is
  'Agenda de Produção (Fase 7d, AG7-14): a folga, em minutos, entre o horário do local conferido e o turno da HBR antes de fechar aquele meio-dia (30). 0..120.';
comment on column public.agenda_config.patio_entrada_antecedencia_du is
  'Agenda de Produção (Fase 7d, AG7-18): a entrada do motorhome no pátio combinada até N dias úteis antes do 1º dia (2). 0..10.';
comment on column public.agenda_config.patio_retirada_du is
  'Agenda de Produção (Fase 7d, AG7-18): o bem sai do pátio N dias úteis depois do fim do serviço (1), quando a retirada não foi dita. 0..5.';
comment on column public.agenda_config.patio_tentativas is
  'Agenda de Produção (Fase 7d): quantas vezes o encaixe tenta depois de achar o pátio cheio (3). Estrutural. 1..6.';
comment on column public.agenda_config.temporada_meses is
  'Agenda de Produção (Fase 7d, AG7-20): os meses de temporada de barco — a fonte ÚNICA (o 7e lê daqui para a folga do barco). Não vazio, de 1 a 12.';
comment on column public.agenda_config.viagem_uf_bate_volta is
  'Agenda de Produção (Fase 7d, AG7-19): as UFs em que o serviço fora da região é ida e volta no dia; outra UF = pernoite. Siglas de 2 letras; vazia = fora da região é sempre pernoite.';
comment on column public.agenda_config.deslocamento_regional_max_min is
  'Agenda de Produção (Fase 7d, AG7-19): até quantos minutos de ida o local é regional, sem custo de capacidade (45). 10..120.';
comment on column public.agenda_config.deslocamento_bate_volta_max_min is
  'Agenda de Produção (Fase 7d, AG7-19): até quantos minutos de ida ainda é ida e volta no dia; acima, pernoite (120). 30..300, maior que o regional.';
comment on column public.agenda_config.deslocamento_fator_estrada is
  'Agenda de Produção (Fase 7d, AG7-19): quanto a estrada é maior que a linha reta entre a base e as coordenadas do local (1,30). 1,00..2,00.';
comment on column public.agenda_config.deslocamento_kmh is
  'Agenda de Produção (Fase 7d, AG7-19): a velocidade média da conta do deslocamento pelas coordenadas (60 km/h). 20..110.';
comment on column public.agenda_config.bate_volta_meios_dia is
  'Agenda de Produção (Fase 7d, AG7-19): quantos meios-dias a ida e volta gasta por dia de serviço (1). 0..1.';
comment on column public.agenda_config.pernoite_ida_meios is
  'Agenda de Produção (Fase 7d, AG7-19): quantos meios-dias de estrada a pernoite gasta na ida e outros tantos na volta (1). 0..2.';
comment on column public.agenda_config.viagem_km_bate_volta is
  'Agenda de Produção (Fase 7d, AG7-19): a reserva da cadeia da viagem, sem local: service_orders.travel_distance_km a partir daqui = ida e volta (120). É o km COBRADO, às vezes a soma de várias idas: último recurso. 20..999.';
comment on column public.agenda_config.viagem_km_pernoite is
  'Agenda de Produção (Fase 7d, AG7-19): a reserva da cadeia da viagem, sem local: travel_distance_km a partir daqui = pernoite (300). 50..2000, maior que o de ida e volta.';
comment on column public.agenda_config.onde_fica_janela_dias is
  'Agenda de Produção (Fase 7d, AG7-21): a porta da aprovação do M11 onde_fica — OS aprovada há até N dias (14). 1..60.';
comment on column public.agenda_config.onde_fica_antes_dias is
  'Agenda de Produção (Fase 7d, AG7-21): a porta do 1º dia do M11 onde_fica — OS com o 1º dia em até N dias corridos (21). 3..60.';
comment on column public.agenda_config.onde_fica_desde is
  'Agenda de Produção (Fase 7d, AG7-21; R6.7a): o M11 onde_fica só alcança OS aprovada a partir deste dia, nas duas portas e também em teste. Nula = ninguém. Gravada pela migration de dado 20261107100900 (só se nula); o DESFAZER a devolve a nula, o que para o M11 sem tirar o tipo da lista.';
comment on column public.agenda_config.local_hora is
  'Agenda de Produção (Fase 7d): a hora da rodada diária do local (16:15: depois do aprender das 16:00, antes da publicação das 16:30). Entre 12:00 e hora_do_plano.';
comment on column public.agenda_config.bem_agua_palavras is
  'Agenda de Produção (Fase 7d, AG7-14): as palavras (expressão regular) da linha de serviço que pedem o bem na água, sobre o texto normalizado. 3..400 letras, validada por _agenda_regex_valido.';
comment on column public.agenda_config.bem_seco_palavras is
  'Agenda de Produção (Fase 7d, AG7-14): as palavras (expressão regular) da linha de serviço que pedem o bem em seco, sobre o texto normalizado. 3..400 letras, validada por _agenda_regex_valido.';

-- ── 2. As tabelas novas ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.agenda_locais (
  id                uuid primary key default gen_random_uuid(),
  marina_id         uuid unique references public.marinas(id) on delete set null,
  nome              text not null check (char_length(nome) between 2 and 80),
  apelidos          text[] not null default '{}' check (cardinality(apelidos) <= 8),
  tipo              text not null check (tipo in ('marina', 'estaleiro', 'patio_hbr', 'patio_parceiro', 'casa_cliente', 'outro')),
  municipio         text not null check (char_length(municipio) between 2 and 60),
  uf                text check (uf ~ '^[A-Z]{2}$'),
  latitude          numeric(9,6) check (latitude between -90 and 90),
  longitude         numeric(9,6) check (longitude between -180 and 180),
  ativo             boolean not null default true,
  abre              time,                      -- manutenção, seg a sex
  fecha             time,
  sabado            text check (sabado in ('nao', 'manha', 'dia')),
  feriado           text not null default 'fecha' check (feriado in ('fecha', 'abre')),
  exige_autorizacao boolean,
  autorizacao_texto text check (char_length(autorizacao_texto) <= 200),
  seguro_exigido    boolean,
  seguro_texto      text check (char_length(seguro_texto) <= 200),
  taxa_texto        text check (char_length(taxa_texto) <= 120),
  tomada_max_w      smallint check (tomada_max_w between 100 and 20000),
  tem_garagem_seca  boolean,
  box_max_min       smallint check (box_max_min between 10 and 600),
  vagas             smallint check (vagas between 1 and 50),
  deslocamento_min  smallint check (deslocamento_min between 0 and 600),   -- a ida, da base da HBR
  viagem            text check (viagem in ('regional', 'bate_volta', 'pernoite')),
  conferido_em      date,
  conferido_por     text check (conferido_por in ('dono', 'marina', 'pesquisa')),
  fonte_texto       text check (char_length(fonte_texto) <= 300),
  nota_dono         text check (char_length(nota_dono) <= 300),
  -- em CASE (o molde de agenda_alocacoes.historico): com AND, um valor que não é lista daria erro de jsonb_array_length, não a recusa
  historico         jsonb not null default '[]'
                      check (case when jsonb_typeof(historico) = 'array' then jsonb_array_length(historico) <= 20 else false end),
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  atualizado_por    uuid,
  constraint local_horario_coerente   check ((abre is null) = (fecha is null) and (abre is null or abre < fecha)),
  constraint local_conferido_coerente check ((conferido_em is null) = (conferido_por is null)),
  constraint local_vagas_so_patio     check (vagas is null or tipo in ('patio_hbr', 'patio_parceiro')),
  constraint local_coordenadas        check ((latitude is null) = (longitude is null))
);
create unique index if not exists agenda_locais_um_patio_hbr on public.agenda_locais ((true)) where tipo = 'patio_hbr' and ativo;

create table if not exists public.os_autorizados (
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  payee_id         uuid not null references public.payees(id),
  local_id         uuid references public.agenda_locais(id) on delete set null,
  valido_ate       date,
  fonte            text not null check (fonte in ('dono', 'cliente')),
  trecho           text check (char_length(trecho) <= 300),
  revogado_em      timestamptz,
  criado_em        timestamptz not null default now(),
  criado_por       uuid,
  primary key (service_order_id, payee_id)
);

comment on table public.agenda_locais is
  'Agenda de Produção (Fase 7d, AG7-14): o cadastro dos locais de serviço, ligado a marinas por marina_id (não vai em marinas porque qualquer usuário logado escreve lá). Regra só vale como regra com conferido_por dono ou marina e dentro de local_conferencia_validade_dias; a pesquisa é nota. Exceção: o feriado do município, fato público, vale sempre. Um só patio_hbr ativo (AG7-18: o espaço da HBR dentro da MP Motorhomes). NUNCA apagada: o local sai por ativo = false. Escrita só por função.';
comment on column public.agenda_locais.apelidos is 'Agenda de Produção (Fase 7d): como o dono e o cliente chamam o local, sem acento e em minúsculas, até 8.';
comment on column public.agenda_locais.abre is 'Agenda de Produção (Fase 7d): a hora em que o local recebe manutenção, seg a sex. Só vale com o local conferido.';
comment on column public.agenda_locais.fecha is 'Agenda de Produção (Fase 7d): a hora em que o local fecha para a manutenção. Só vale com o local conferido.';
comment on column public.agenda_locais.sabado is 'Agenda de Produção (Fase 7d): nao, manha ou dia. Nulo = não sei. Só vale com o local conferido.';
comment on column public.agenda_locais.feriado is 'Agenda de Produção (Fase 7d): fecha (o padrão) ou abre no feriado do município; abre só vale com o local conferido.';
comment on column public.agenda_locais.exige_autorizacao is 'Agenda de Produção (Fase 7d, AG7-14): o local pede autorização nominal. Dado do preparo do acesso, nunca filtro de pessoa.';
comment on column public.agenda_locais.vagas is 'Agenda de Produção (Fase 7d, AG7-18): quantos bens cabem no pátio; nulo = só conta, não limita. Só em patio_hbr e patio_parceiro.';
comment on column public.agenda_locais.deslocamento_min is 'Agenda de Produção (Fase 7d, AG7-19): a ida da base da HBR, em minutos, quando foi dita. Vale sobre o cálculo pelas coordenadas.';
comment on column public.agenda_locais.viagem is 'Agenda de Produção (Fase 7d, AG7-19): a classe de viagem dita no cadastro; nula = a cadeia calcula.';
comment on column public.agenda_locais.conferido_em is 'Agenda de Produção (Fase 7d, AG7-14): quando a regra foi conferida. Junto com conferido_por: os dois ou nenhum.';
comment on column public.agenda_locais.conferido_por is 'Agenda de Produção (Fase 7d, AG7-14): dono e marina valem como regra (_agenda_local_conferido); pesquisa é só nota.';
comment on column public.agenda_locais.fonte_texto is 'Agenda de Produção (Fase 7d): de onde veio a regra (o regimento, com os itens).';
comment on column public.agenda_locais.nota_dono is 'Agenda de Produção (Fase 7d): o que o dono disse do local, nas palavras dele.';
comment on column public.agenda_locais.historico is 'Agenda de Produção (Fase 7d): as mudanças das colunas de regra ({em, por, antes, depois}), as 20 mais novas. Só o gatilho escreve.';

comment on table public.os_autorizados is
  'Agenda de Produção (Fase 7d, AG7-14): quem está autorizado no local da OS. É DADO do preparo do acesso (a OS tem o acesso combinado quando todas as pessoas alocadas, sem o dono, estão aqui), NUNCA filtro de pessoa do motor. NUNCA apagada: a autorização sai por revogado_em. Escrita só por função.';
comment on column public.os_autorizados.valido_ate is 'Agenda de Produção (Fase 7d): até quando a autorização vale (o último dia da OS no local); nulo = sem data.';
comment on column public.os_autorizados.fonte is 'Agenda de Produção (Fase 7d): dono ou cliente: quem disse.';
comment on column public.os_autorizados.trecho is 'Agenda de Produção (Fase 7d): as palavras de quem disse.';
comment on column public.os_autorizados.revogado_em is 'Agenda de Produção (Fase 7d): a autorização deixou de valer aqui (o *desfaz* e a revogação gravam; a linha fica).';

-- O histórico e o atualizado_em de agenda_locais (§4.3). Só as colunas de regra entram no histórico; quem escreve o historico é só este
-- gatilho (o valor que vier no UPDATE é ignorado).
create or replace function public._agenda_locais_historico()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  c_regra constant text[] := array['tipo', 'municipio', 'uf', 'latitude', 'longitude', 'ativo', 'abre', 'fecha', 'sabado', 'feriado',
                                   'exige_autorizacao', 'autorizacao_texto', 'seguro_exigido', 'seguro_texto', 'taxa_texto',
                                   'tomada_max_w', 'tem_garagem_seca', 'box_max_min', 'vagas', 'deslocamento_min', 'viagem',
                                   'conferido_em', 'conferido_por', 'nota_dono'];
  v_velho  jsonb := to_jsonb(old);
  v_novo   jsonb := to_jsonb(new);
  v_antes  jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_h      jsonb := old.historico;
  k        text;
begin
  new.atualizado_em := now();
  foreach k in array c_regra loop
    if v_velho -> k is distinct from v_novo -> k then
      v_antes := v_antes || jsonb_build_object(k, v_velho -> k);
      v_depois := v_depois || jsonb_build_object(k, v_novo -> k);
    end if;
  end loop;
  if v_antes <> '{}'::jsonb then
    v_h := v_h || jsonb_build_array(jsonb_build_object('em', now(), 'por', new.atualizado_por, 'antes', v_antes, 'depois', v_depois));
    if jsonb_array_length(v_h) > 20 then
      select jsonb_agg(e order by o) into v_h
        from jsonb_array_elements(v_h) with ordinality t(e, o)
       where o > jsonb_array_length(v_h) - 20;
    end if;
  end if;
  new.historico := v_h;
  return new;
end;
$function$;

comment on function public._agenda_locais_historico() is
  'Agenda de Produção (Fase 7d, P1): gatilho BEFORE UPDATE de agenda_locais — põe atualizado_em e guarda em historico {em, por, antes, depois} das colunas de regra que mudaram, as 20 entradas mais novas. Sem mudança de regra, o historico fica como estava; o que vier no UPDATE é ignorado.';

drop trigger if exists agenda_locais_nao_apaga on public.agenda_locais;
create trigger agenda_locais_nao_apaga before delete on public.agenda_locais
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_locais_historico on public.agenda_locais;
create trigger agenda_locais_historico before update on public.agenda_locais
  for each row execute function public._agenda_locais_historico();
drop trigger if exists os_autorizados_nao_apaga on public.os_autorizados;
create trigger os_autorizados_nao_apaga before delete on public.os_autorizados
  for each row execute function public._agenda_registro_nao_apaga();

alter table public.agenda_locais  enable row level security;
alter table public.os_autorizados enable row level security;

drop policy if exists agenda_locais_leitura on public.agenda_locais;
create policy agenda_locais_leitura on public.agenda_locais
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));
drop policy if exists os_autorizados_leitura on public.os_autorizados;
create policy os_autorizados_leitura on public.os_autorizados
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.agenda_locais, public.os_autorizados from public, anon, authenticated;
grant select on table public.agenda_locais, public.os_autorizados to authenticated;
grant all on table public.agenda_locais, public.os_autorizados to service_role;

-- ── 3. As colunas novas do planejamento da OS ───────────────────────────────────────────────────────
-- A FK de local_id vem depois do create table da seção 2. Escrevem só: _agenda_aplicar_planejar (o *grava* do dono, P7),
-- _agenda_local_decidir (as perguntas local e combinar, P5 e P6) e o desfazer delas.
alter table public.os_planejamento
  add column if not exists local_id             uuid references public.agenda_locais(id) on delete set null,
  add column if not exists local_fonte          text check (local_fonte in ('dono', 'cliente')),
  add column if not exists local_em             timestamptz,
  add column if not exists bem_situacao         text check (bem_situacao in ('agua', 'seco', 'garagem_seca', 'patio', 'com_cliente')),
  add column if not exists bem_situacao_fonte   text check (bem_situacao_fonte in ('dono', 'cliente')),
  add column if not exists bem_situacao_em      timestamptz,
  add column if not exists bem_exige            text check (bem_exige in ('agua', 'seco', 'tanto_faz')),
  add column if not exists descer_quem          text check (char_length(descer_quem) between 2 and 80),
  add column if not exists entrada_em           date,
  add column if not exists retirada_em          date,
  add column if not exists entrada_fonte        text check (entrada_fonte in ('dono', 'cliente')),
  add column if not exists viagem               text check (viagem in ('regional', 'bate_volta', 'pernoite')),
  add column if not exists reserva_marina_ok_em timestamptz,
  add column if not exists descida_ok_em        timestamptz;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('local_coerente',      'check ((local_id is null) = (local_fonte is null))'),
      ('situacao_coerente',   'check ((bem_situacao is null) = (bem_situacao_fonte is null))'),
      ('entrada_coerente',    'check ((coalesce(entrada_em, retirada_em) is null) = (entrada_fonte is null))'),
      ('entrada_antes_saida', 'check (entrada_em is null or retirada_em is null or entrada_em < retirada_em)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.os_planejamento'::regclass and conname = r.nome) then
      execute format('alter table public.os_planejamento add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.os_planejamento.local_id is
  'Agenda de Produção (Fase 7d, AG7-14): o local dito pelo dono ou pelo cliente (com o sim do dono). É o 1º da cadeia de _agenda_local_resolvido.';
comment on column public.os_planejamento.local_fonte is 'Agenda de Produção (Fase 7d): dono ou cliente: quem disse o local. Junto com local_id: os dois ou nenhum.';
comment on column public.os_planejamento.local_em is 'Agenda de Produção (Fase 7d): quando o local foi dito.';
comment on column public.os_planejamento.bem_situacao is
  'Agenda de Produção (Fase 7d, AG7-14): onde o bem está: agua, seco, garagem_seca, patio, com_cliente. Nulo = não sei.';
comment on column public.os_planejamento.bem_situacao_fonte is 'Agenda de Produção (Fase 7d): dono ou cliente. Junto com bem_situacao: os dois ou nenhum.';
comment on column public.os_planejamento.bem_situacao_em is 'Agenda de Produção (Fase 7d): quando o estado do bem foi dito.';
comment on column public.os_planejamento.bem_exige is
  'Agenda de Produção (Fase 7d, AG7-14): como o serviço pede o bem, dito pelo dono: agua, seco ou tanto_faz. Nulo = a palavra da linha de serviço decide.';
comment on column public.os_planejamento.descer_quem is 'Agenda de Produção (Fase 7d, AG7-14): quem desce o barco para o teste na água, nas palavras de quem disse.';
comment on column public.os_planejamento.entrada_em is 'Agenda de Produção (Fase 7d, AG7-18): o dia em que o motorhome entra no pátio.';
comment on column public.os_planejamento.retirada_em is 'Agenda de Produção (Fase 7d, AG7-18): o dia em que o motorhome sai do pátio: fecha os dias a partir dele.';
comment on column public.os_planejamento.entrada_fonte is 'Agenda de Produção (Fase 7d): dono ou cliente. Com entrada_em ou retirada_em, obrigatória.';
comment on column public.os_planejamento.viagem is
  'Agenda de Produção (Fase 7d, AG7-19): a viagem dita pelo dono: regional, bate_volta ou pernoite. É o 1º da cadeia de _agenda_viagem_da_os.';
comment on column public.os_planejamento.reserva_marina_ok_em is 'Agenda de Produção (Fase 7d, AG7-14): o fato combinado: a vaga na garagem seca foi reservada.';
comment on column public.os_planejamento.descida_ok_em is 'Agenda de Produção (Fase 7d, AG7-14): o fato combinado: a descida para o teste na água foi combinada.';

-- ── 4. As listas fechadas (pelo ampliador da 7a: lê a lista viva e soma) ────────────────────────────
select public._agenda_ampliar_lista('public.agenda_perguntas', 'agenda_perguntas_tipo_check', 'tipo', array['local', 'combinar', 'acesso']);
select public._agenda_ampliar_lista('public.agenda_acoes', 'agenda_acoes_tipo_check', 'tipo', array['local']);
select public._agenda_ampliar_lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', 'rotina', array['local']);
select public._agenda_ampliar_lista('public.agenda_alocacoes', 'agenda_alocacoes_cancelada_motivo_check', 'cancelada_motivo', array['local']);
select public._agenda_ampliar_lista('public.agenda_cliente_mensagens', 'agenda_cliente_mensagens_tipo_check', 'tipo', array['onde_fica']);

comment on column public.agenda_vigia_rodadas.rotina is
  'Agenda de Produção (Fase 3): vigia (o tique da Fase 2) ou rotina (a rotina da equipe e da diária); Fase 4: material (a nota, o Pix, o detector e a mensagem ao fornecedor); Fase 5: cliente (as mensagens-modelo ao cliente); Fase 6: aprender (a medição e o aprendizado, uma vez por dia); Fase 7a: gestor (a rodada do gestor da agenda, o job agenda-gestor); Fase 7b: equipe_semana (a pergunta da semana, o passo 0b1 do task-automations); Fase 7c: habilidade (a rodada de quem faz o quê, o passo 0b2a). As rodadas de antes são da vigia. Fase 7c (P8): tarefas (a rodada das etapas do dia). Fase 7d: local (a rodada diária do local: combinar e conflitos).';

-- À MÃO (R6.4): este CHECK é "cliente_tipos_ligados <@ array[...]", e o ampliador só aceita "coluna = ANY (array[...])": daria 22023 e a
-- migration cairia. Molde de 20261028100000:103. Só se ainda não tem o valor (rodar de novo não recria). O valor da linha continua com os
-- 11 tipos: onde_fica fica fora da lista, em teste.
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.agenda_config'::regclass and conname = 'agenda_config_cliente_tipos_ligados_check'
                    and pg_get_constraintdef(oid) like '%''onde_fica''%') then
    alter table public.agenda_config drop constraint if exists agenda_config_cliente_tipos_ligados_check;
    alter table public.agenda_config add constraint agenda_config_cliente_tipos_ligados_check
      check (cliente_tipos_ligados <@ array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data',
                                            'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia', 'onde_fica']::text[]);
  end if;
end
$$;

-- ── 5. As colunas geradas ───────────────────────────────────────────────────────────────────────────
-- acesso passa a ser crítica (a decisão urgente de D-1, AG7-14); local e combinar não são. SET EXPRESSION (Postgres 17+, o molde de
-- 20261031100000) mantém a coluna no lugar e reconstrói e revalida critica_tem_opcoes, critica_decidida e veto_nao_critica com o mesmo
-- nome. Só se a expressão ainda não tem 'acesso'. É a expressão de hoje (os 12 tipos, conferidos em produção em 05/11) + acesso; o 7g
-- copia DESTA.
do $$
begin
  if exists (select 1
               from pg_attribute a
               join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
              where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica' and a.attgenerated = 's'
                and pg_get_expr(d.adbin, d.adrelid) not like '%''acesso''%') then
    if current_setting('server_version_num')::int < 170000 then
      raise exception 'agenda_perguntas.critica: esta migration precisa do Postgres 17 ou mais novo (ALTER COLUMN … SET EXPRESSION); este é o %.',
        current_setting('server_version');
    end if;
    alter table public.agenda_perguntas alter column critica set expression as
      (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono','diaria','cliente_aviso',
                'aprendizado','onda','dia_avisado','dia_prometido','sabado','acesso'));
  end if;
end
$$;

-- onde_fica = M11 (o semana da 7f será M12); sem isto cairia no else M10. Nunca mudada por SET EXPRESSION antes: o molde é o da critica.
-- É a expressão de hoje (conferida em produção em 05/11) + onde_fica. Nenhum índice nem view depende de modelo (R6.4). Só se a expressão
-- ainda não tem 'onde_fica'.
do $$
begin
  if exists (select 1
               from pg_attribute a
               join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
              where a.attrelid = 'public.agenda_cliente_mensagens'::regclass and a.attname = 'modelo' and a.attgenerated = 's'
                and pg_get_expr(d.adbin, d.adrelid) not like '%''onde_fica''%') then
    if current_setting('server_version_num')::int < 170000 then
      raise exception 'agenda_cliente_mensagens.modelo: esta migration precisa do Postgres 17 ou mais novo (ALTER COLUMN … SET EXPRESSION); este é o %.',
        current_setting('server_version');
    end if;
    alter table public.agenda_cliente_mensagens alter column modelo set expression as
      (case tipo
         when 'confirmar' then 'M1' when 'vespera' then 'M2' when 'material_chegou' then 'M3'
         when 'acesso' then 'M4' when 'andamento' then 'M5' when 'pode_atrasar' then 'M6'
         when 'nova_data' then 'M7' when 'pronto' then 'M8' when 'pronto_lembrete' then 'M8'
         when 'pos_servico' then 'M9' when 'onde_fica' then 'M11' else 'M10' end);
  end if;
end
$$;

comment on column public.agenda_cliente_mensagens.modelo is
  'Agenda de Produção (Fase 5; Fase 7d): o modelo da mensagem, gerado do tipo — M1 confirmar, M2 vespera, M3 material_chegou, M4 acesso, M5 andamento, M6 pode_atrasar, M7 nova_data, M8 pronto e pronto_lembrete, M9 pos_servico, M11 onde_fica; o resto (mudanca_no_dia), M10.';

-- ── 6. As leituras ──────────────────────────────────────────────────────────────────────────────────
-- A regra do conferido (§3.1, item 8): conferido_por dono ou marina e conferido_em dentro de local_conferencia_validade_dias. A pesquisa
-- nunca é conferida. Local inexistente, inativo ou fora do alcance de quem lê (a RLS de agenda_locais) = false.
create or replace function public._agenda_local_conferido(p_local uuid, p_hoje date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce((
    select l.conferido_por in ('dono', 'marina')
           and l.conferido_em >= p_hoje - (public._agenda_cfg()).local_conferencia_validade_dias
      from public.agenda_locais l
     where l.id = p_local and l.ativo), false);
$function$;

comment on function public._agenda_local_conferido(uuid, date) is
  'Agenda de Produção (Fase 7d, P1; AG7-14): o local está conferido em p_hoje? conferido_por dono ou marina e conferido_em >= p_hoje - local_conferencia_validade_dias. A pesquisa nunca é conferida (vira nota). Local inexistente ou inativo = false. STABLE, invoker: sob a RLS de agenda_locais.';

-- O modo efetivo do local (R6.7b, molde de _agenda_gestor_modo): com *gestor, só propor*, o que está ligado vale sombra (o desligado
-- continua desligado). Sem isto, um modo da 7d ligado poderia replanejar sem a rede K: o freio desliga a onda
-- (_agenda_gestor_regra('onda') exige not gestor_so_propor). Todo leitor de modo da 7d usa esta função, nunca cf.modo_x.
create or replace function public._agenda_local_modo(p_qual text)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_modo text;
begin
  if p_qual is null or p_qual <> all (array['calendario', 'acesso', 'bem', 'patio', 'viagem', 'mesmo_local']) then
    raise exception '_agenda_local_modo: o modo "%" não existe.', p_qual using errcode = '22023';
  end if;
  cf := public._agenda_cfg();
  v_modo := case p_qual
              when 'calendario'  then cf.modo_local_calendario
              when 'acesso'      then cf.modo_local_autorizacao
              when 'bem'         then cf.modo_bem
              when 'patio'       then cf.modo_patio
              when 'viagem'      then cf.modo_viagem
              when 'mesmo_local' then cf.modo_mesmo_local
            end;
  if cf.gestor_so_propor and v_modo = 'ligado' then
    return 'sombra';
  end if;
  return v_modo;
end;
$function$;

comment on function public._agenda_local_modo(text) is
  'Agenda de Produção (Fase 7d, P1; R6.7b): o modo EFETIVO (desligado | sombra | ligado) de calendario (modo_local_calendario), acesso (modo_local_autorizacao), bem (modo_bem), patio (modo_patio), viagem (modo_viagem) e mesmo_local (modo_mesmo_local). Com *gestor, só propor* (gestor_so_propor), o que está ligado vale sombra; o desligado continua desligado. Todo leitor de modo da 7d usa esta função, nunca cf.modo_x; a exceção é _agenda_modo_da_pergunta, que devolve o modo cru (a pergunta já aberta continua respondível). Outro nome = 22023. STABLE, invoker.';

-- ── 7. A recriada ───────────────────────────────────────────────────────────────────────────────────
-- _agenda_modo_da_pergunta (de 20261102100550_agenda_fase7c_tarefas.sql)
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
    -- FASE 7d: (7d P1, R6.3-1) as perguntas do local: o modo CRU, sem o freio de *gestor, só propor* (R6.7b): a pergunta já aberta
    -- continua respondível, e quem abre pergunta nova lê _agenda_local_modo. local é da mensagem ao cliente (nasce da resposta ao M11);
    -- combinar é do interruptor do que se combina, pela chave combinar:<tipo>:<os>:<para>; o resto, combinar:acesso:… incluído, é do
    -- preparo do acesso, como a crítica acesso.
    when p_tipo = 'local' then c.modo_cliente
    when p_tipo = 'combinar' and coalesce(p_chave, '') like 'combinar:reserva_marina:%' then c.modo_bem
    when p_tipo = 'combinar' and coalesce(p_chave, '') like 'combinar:descida:%' then c.modo_bem
    when p_tipo = 'combinar' and coalesce(p_chave, '') like 'combinar:entrada:%' then c.modo_patio
    when p_tipo in ('combinar', 'acesso') then c.modo_local_autorizacao
    -- FASE 7d: fim
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
  'Agenda de Produção (correção de 29/10, P3): o modo de agenda_config de quem grava cada tipo de pergunta — críticas do plano: modo_proposta; conferencia, chegou, parada, estouro, duracao, material_conferir, padrao_do_dono, entrega: modo_vigia; chegou:fornecedor:…, nfe_vincular, pix_material, previsao_fornecedor, fornecedor_cadastro, fornecedores_prazo: modo_material; diaria, diaria_ligar: modo_diaria; equipe_resposta, concluir: modo_equipe; cliente_*: modo_cliente; aprendizado: modo_aprendizado; outro tipo: null. A limpeza da vigia fecha a pergunta aberta em sombra quando este modo está ligado. STABLE, invoker, só o service_role. CORREÇÃO 29/10 (revisão): o tipo novo equipe_sem_dias é da vigia (modo_vigia). Fase 7a (P1): dia_avisado e dia_prometido = modo_proposta (críticas do plano); reavaliar e reestimar = o modo da revisão do gestor; compre_ate = o da cobrança; situacao, estimativa, equipe_cadastro, ficha_estimativa, bem_livre, sinal, onda e sabado = o do gestor que marca (_agenda_gestor_modo). Fase 7a (P11): ficha_estimativa = modo_equipe (a pergunta é das mensagens à equipe: a proteção da ficha vale com *gestor, só propor*); o bloco vem antes da linha do P1, que ainda a cita. Fase 7b (P1): dias_semana = modo_dias (a pergunta dos dias da semana ao dono); equipe_cadastro = modo_cadastro fora de desligado (a chamada da equipe passa a ser da 7b), senão o do gestor que marca, como antes. Fase 7c (P1): habilidade = modo_habilidade_propor (a pergunta de quem faz o quê da equipe, habilidade:equipe:…) ou modo_habilidade (a de uma OS, habilidade:os:<os>). FASE 7c (P8, R5.4): o tipo tarefa (tarefa:prazo:<os> e tarefa:quem:<os>, as exceções das etapas) é do modo_tarefas. Fase 7d (P1; R6.3-1): local = modo_cliente; acesso = modo_local_autorizacao; combinar pela chave (combinar:reserva_marina:… e combinar:descida:… = modo_bem; combinar:entrada:… = modo_patio; o resto, combinar:acesso:… incluído, = modo_local_autorizacao). O modo CRU, sem o freio de *gestor, só propor* (R6.7b): quem abre pergunta nova lê _agenda_local_modo.';

-- ── 8. Portas ───────────────────────────────────────────────────────────────────────────────────────
-- _agenda_modo_da_pergunta: create or replace mantém a porta de antes (só o service_role).
revoke all on function public._agenda_locais_historico() from public, anon, authenticated;
revoke all on function public._agenda_local_conferido(uuid, date), public._agenda_local_modo(text) from public, anon;
grant execute on function public._agenda_local_conferido(uuid, date), public._agenda_local_modo(text) to authenticated, service_role;
