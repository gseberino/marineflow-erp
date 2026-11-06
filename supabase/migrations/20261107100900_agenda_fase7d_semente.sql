-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), pacote P8: a semente dos locais, a trava do M11 e os 6 modos de desligado para SOMBRA (o dado).
-- Spec: spec-fase7d.md §5.9, §6.5, §10, com R2, R6.5 (AG7-18: a MP Motorhomes é o pátio da HBR, 8 locais, nenhum pátio em Itajaí), R6.7a (onde_fica_desde) e R6.11. Nomes: fase7-registro.md.
-- Respostas do dono de 29/10 e 31/10 (fase7-padroes.md): AG7-01 "ligar direto quando estiver pronto"; AG7-14 a regra de marina é nota até ele conferir; AG7-18 um local só, o espaço da
-- HBR no pátio da MP Motorhomes, em Balneário Camboriú. A publicação nunca liga às cegas: este arquivo põe tudo em teste, e cada *ligar* é um UPDATE no MESMO dia, depois do pós-deploy
-- verde e da 1ª rodada em teste sem erro, pelo roteiro (o "por quê", na linguagem do dono, em fila-do-dono/fase7d-oks.md).
--
-- ═══ GRAVA DADO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão. Aplica DEPOIS das migrations de estrutura da 7d (20261107100000 .. 100700) e das funções de borda (R6.11, passos 1 a 3).
--
-- O QUE FAZ:
--   1. agenda_locais: uma linha por marina ativa, menos as de nome com "teste" (on conflict (marina_id): a que o DESFAZER inativou volta a ativa; a ativa não muda). Hoje são 8. Tipo: Kalmar Estaleiro = estaleiro; MP Motorhomes =
--      patio_hbr, com deslocamento_min 0, vagas nulo (só conta) e a nota do dono; o resto = marina. Os apelidos da §6.5. Nenhum pátio em Itajaí (AG7-18).
--   2. A Marina Itajaí como NOTA (conferido_por = pesquisa): o regimento de 2024. A Tedesco com a garagem seca, também pesquisa. Nada disso é regra: só com conferido_por dono ou
--      marina (AG7-14). O feriado do município é fato público e vale com o modo ligado, sem conferir. As outras ficam só com o cadastro.
--   3. agenda_config.onde_fica_desde = o dia deste dado, SÓ SE NULA: é a trava do M11 (R6.7a). Entra só OS aprovada a partir dela, e nenhuma das 11 de hoje recebe.
--   4. Os 6 modos: de desligado para sombra, cada um só se estiver desligado. NUNCA rebaixa ligado nem mexe no que já está em sombra.
--   Não toca cliente_tipos_ligados: o M11 entra na lista só com "OK mandar a pergunta onde fica". Não toca nenhum modo das Fases 1–6 nem de 7a–7c, nem número nenhum de agenda_config.
--   atualizado_em e atualizado_por só mudam na linha que mudou (atualizado_por = null: foi a migration, não uma pessoa).
--
-- EM SOMBRA: o motor, a ficha, o fechamento e as mensagens são os de antes, byte a byte (o M1 e o M1c de agenda_fase7d_motor.sql e o C8j de agenda_fase7d_combinar.sql). Aparecem o foco
-- *agenda locais*, o bloco Local do cartão e as ações "Em teste" da rodada do local (uma vez por dia, a partir das 16:15). Nada sai a ninguém.
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar):
--   npx supabase@2.111.0 db query --linked -e "select c.modo_local_calendario, c.modo_local_autorizacao, c.modo_bem, c.modo_patio, c.modo_viagem, c.modo_mesmo_local, c.onde_fica_desde,
--     (select count(*) from public.agenda_locais) as locais, (select count(*) from public.marinas m where m.active and m.name !~* 'teste') as marinas from public.agenda_config c;"
--   Esperado: desligado nos 6, onde_fica_desde nula, locais 0, marinas 8.
--
-- APLICAR (CLAUDE.md, regra 1 — pelo OK permanente "publicar em teste cada etapa quando o pós-deploy der verde", passo 3 do R6.11; antes do tique seguinte):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261107100900_agenda_fase7d_semente.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name) values ('20261107100900', 'agenda_fase7d_semente');"
--   (o roteiro faz os dois pelo publicar/exec/aplicar.sh, que registra e para na 1ª falha)
--
-- PROVA DEPOIS (só leitura): o SELECT do fim deste arquivo; supabase/tests/agenda_fase7d_pos_deploy.sql (M2 "registrada", C2 com os 6 em sombra); na 1ª rodada depois das 16:15,
-- agenda_saude() -> 'local' sem erro.
--
-- IDEMPOTENTE: rodar de novo não muda nada (o insert só reativa o que estiver inativo; o update só pega desligado e onde_fica_desde nula). Depois do DESFAZER, rodar de novo traz os locais de volta. A bancada NÃO aplica este arquivo
-- (scripts/bancada-agenda/bancada.mjs, FORA_DA_BANCADA): supabase/tests/agenda_fase7d_semente.sql o roda numa subtransação desfeita.
--
-- DESFAZER (só se o dono pedir; nada é apagado: as linhas nunca se apagam). É UM comando só (do "with" ao ";"). Só volta o que está em sombra e diz quais ficaram ligados: para parar um
-- modo ligado, ele vai a sombra primeiro (o DESFAZER de publicar/exec/ligar-fase7d.sql). onde_fica_desde = null para o M11 sem tirar o tipo da lista. As linhas da semente ficam inativas:
-- saem da cadeia, e a OS volta à suposição. A pergunta combinar ou acesso que estiver aberta é descartada pela rodada do local, no tique seguinte (o modo voltou). O que o dono ou o
-- cliente gravou numa OS fica.
-- DESFAZER-INICIO
--   with modos as (
--     update public.agenda_config set modo_local_calendario = case when modo_local_calendario = 'sombra' then 'desligado' else modo_local_calendario end, modo_local_autorizacao = case when modo_local_autorizacao = 'sombra' then 'desligado' else modo_local_autorizacao end, modo_bem = case when modo_bem = 'sombra' then 'desligado' else modo_bem end, modo_patio = case when modo_patio = 'sombra' then 'desligado' else modo_patio end, modo_viagem = case when modo_viagem = 'sombra' then 'desligado' else modo_viagem end, modo_mesmo_local = case when modo_mesmo_local = 'sombra' then 'desligado' else modo_mesmo_local end, onde_fica_desde = null, atualizado_em = now(), atualizado_por = null
--      where id
--     returning modo_local_calendario, modo_local_autorizacao, modo_bem, modo_patio, modo_viagem, modo_mesmo_local
--   ), locais as (
--     update public.agenda_locais l set ativo = false, atualizado_por = null
--      where l.ativo and l.marina_id is not null and l.conferido_por is distinct from 'dono' and l.conferido_por is distinct from 'marina'
--     returning 1
--   )
--   select (select count(*) from locais) as locais_inativos, (select to_jsonb(m) from modos m) as modos;
-- DESFAZER-FIM
-- (O local que o dono ou a marina conferiu fica ativo, e o lugar novo e a casa do cliente que o dono criou pela conversa não são da semente: a palavra dele não se desfaz por aqui. Para tirar um: update public.agenda_locais set ativo = false where id = …)

-- 1 e 2. Os locais: a semente da §5.9, com os apelidos da §6.5. Só pesquisa em conferido_por: nunca vira regra sozinha (AG7-14).
insert into public.agenda_locais (marina_id, nome, apelidos, tipo, municipio, uf, latitude, longitude, deslocamento_min, nota_dono, abre, fecha, sabado, feriado,
                                  exige_autorizacao, autorizacao_texto, seguro_exigido, seguro_texto, taxa_texto, tomada_max_w, tem_garagem_seca, box_max_min,
                                  conferido_em, conferido_por, fonte_texto)
select m.id, m.name, coalesce(a.apelidos, '{}'), coalesce(a.tipo, 'marina'), btrim(m.city), case when m.state ~ '^[A-Z]{2}$' then m.state end, m.latitude, m.longitude,
       case when a.tipo = 'patio_hbr' then 0 end,
       case when a.tipo = 'patio_hbr' then 'O espaço da HBR fica dentro do pátio da MP Motorhomes, em Balneário Camboriú (AG7-18). Quantos motorhomes cabem: a dizer.' end,
       r.abre, r.fecha, r.sabado, coalesce(r.feriado, 'fecha'), r.exige_autorizacao, r.autorizacao_texto, r.seguro_exigido, r.seguro_texto, r.taxa_texto, r.tomada_max_w,
       r.tem_garagem_seca, r.box_max_min,
       case when r.nome is not null then date '2026-10-29' end, case when r.nome is not null then 'pesquisa' end, r.fonte_texto
  from public.marinas m
  left join (values
    ('Marina Itajaí',               array['marina de itajai', 'marina itajai'],                                                               'marina'),
    ('Kalmar Estaleiro',            array['kalmar', 'estaleiro kalmar'],                                                                      'estaleiro'),
    ('MP Motorhomes',               array['mp motorhomes', 'mp motorhome', 'mp motor home', 'patio', 'patio da hbr', 'oficina', 'na hbr', 'com voces'], 'patio_hbr'),
    ('Tedesco Marina Garden Plaza', array['tedesco', 'garden plaza'],                                                                         'marina'),
    ('Iate Clube Caiobá',           array['caioba', 'iate clube caioba'],                                                                     'marina'),
    ('Marina do Sol',               array['marina do sol'],                                                                                   'marina'),
    ('Ponta do Poço Marina Clube',  array['ponta do poco'],                                                                                   'marina'),
    ('Veleiros da Ilha',            array['veleiros da ilha'],                                                                                'marina')
  ) as a(nome, apelidos, tipo) on a.nome = m.name
  left join (values
    ('Marina Itajaí', time '08:00', time '18:00', 'manha', 'fecha', true,
     'autorização escrita do dono do barco com nome e documento de quem vai e as datas', true, 'seguro de responsabilidade civil com a marina como segurada adicional',
     'taxa de prestador na portaria de serviço', 1200::smallint, true, 60::smallint,
     'Regimento Interno da Marina Itajaí, 2024 (itens 2.2, 6.3, 8.2, 8.12, 8.13, 16.6, 16.8 e seção 10). Os itens 8.3 e 16.8 se contradizem sobre feriado.'),
    ('Tedesco Marina Garden Plaza', null::time, null::time, null, null, null, null, null, null, null, null::smallint, true, null::smallint,
     'Pesquisa de 29/10/2026: 3 hangares de até 4 andares.')
  ) as r(nome, abre, fecha, sabado, feriado, exige_autorizacao, autorizacao_texto, seguro_exigido, seguro_texto, taxa_texto, tomada_max_w, tem_garagem_seca, box_max_min, fonte_texto)
    on r.nome = m.name
 where m.active and m.name !~* 'teste' and nullif(btrim(m.city), '') is not null
-- (correção C7) a linha que o DESFAZER inativou volta; a ativa não muda (nem a hora)
on conflict (marina_id) do update set ativo = true, atualizado_por = null where not public.agenda_locais.ativo;

-- 3 e 4. A trava do M11 (só se nula) e os 6 modos (cada um só se estiver desligado).
update public.agenda_config
   set modo_local_calendario  = case when modo_local_calendario = 'desligado' then 'sombra' else modo_local_calendario end,
       modo_local_autorizacao = case when modo_local_autorizacao = 'desligado' then 'sombra' else modo_local_autorizacao end,
       modo_bem               = case when modo_bem = 'desligado' then 'sombra' else modo_bem end,
       modo_patio             = case when modo_patio = 'desligado' then 'sombra' else modo_patio end,
       modo_viagem            = case when modo_viagem = 'desligado' then 'sombra' else modo_viagem end,
       modo_mesmo_local       = case when modo_mesmo_local = 'desligado' then 'sombra' else modo_mesmo_local end,
       onde_fica_desde        = coalesce(onde_fica_desde, public._hoje_brt()),
       atualizado_em          = now(),
       atualizado_por         = null
 where id
   and ('desligado' in (modo_local_calendario, modo_local_autorizacao, modo_bem, modo_patio, modo_viagem, modo_mesmo_local) or onde_fica_desde is null);

-- O estado depois: os locais e os modos (os das etapas de antes, para conferir que não mudaram).
select (select count(*) from public.agenda_locais l where l.ativo) as locais, (select string_agg(l.nome || ' (' || l.tipo || ')', ', ' order by l.nome) from public.agenda_locais l) as quais,
       c.modo_local_calendario, c.modo_local_autorizacao, c.modo_bem, c.modo_patio, c.modo_viagem, c.modo_mesmo_local, c.onde_fica_desde, c.cliente_tipos_ligados,
       c.modo_cliente, c.modo_marcar_sozinho, c.gestor_so_propor, c.modo_dias, c.modo_habilidade, c.modo_tarefas
  from public.agenda_config c;
