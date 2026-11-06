-- Prova da migration de dado da Fase 7d da Agenda de Produção (pacote P8; 20261107100900_agenda_fase7d_semente.sql), que a bancada NÃO aplica (FORA_DA_BANCADA): aqui ela roda como está,
-- dentro da transação do teste, desfeita no fim (spec-fase7d §5.9, §6.5, §8.3 agenda_fase7d_semente.sql, §10, R2, R6.5, R6.7a, R6.11).
-- bancada: depende de 20261107100700
--
--   S1  os locais: 8, a MP como o pátio da HBR, nenhum pátio em Itajaí, os apelidos da §6.5; a marina de teste, a inativa e a sem cidade ficam de fora
--   S2  a Marina Itajaí e a Tedesco como NOTA: não conferidas (AG7-14); as outras só com o cadastro; a nota do pátio
--   S3  os 6 modos: desligado → sombra; ligado nunca é rebaixado; onde_fica_desde só se nula; o resto de agenda_config igual
--   S4  idempotente: de novo não muda nada (nem a hora)
--   S5  com a semente: a cadeia do local, o resolvedor, o foco e a saúde; o M11 continua fora da lista
--   S6  o DESFAZER do cabeçalho: um comando só, nenhum DELETE; volta teste a desligado, não mexe no ligado nem no que o dono conferiu; as linhas ficam
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora dela sai PULADO (sem agenda_teste.mig_semente_fase7d). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
-- A foto do que o dado pode mudar, sem o que muda sozinho
create function pg_temp.foto_locais() returns text language sql stable as $f$
  select md5(coalesce(string_agg(to_jsonb(l)::text, '|' order by l.nome), '')) from public.agenda_locais l
$f$;
create function pg_temp.foto_config() returns text language sql stable as $f$
  select md5((to_jsonb(c))::text) from public.agenda_config c where c.id
$f$;
-- agenda_config sem o que o dado grava
create function pg_temp.resto_config() returns text language sql stable as $f$
  select md5((to_jsonb(c) - array['modo_local_calendario', 'modo_local_autorizacao', 'modo_bem', 'modo_patio', 'modo_viagem', 'modo_mesmo_local', 'onde_fica_desde',
                                  'atualizado_em', 'atualizado_por'])::text)
    from public.agenda_config c where c.id
$f$;
-- O DESFAZER do cabeçalho, como está escrito: as linhas entre as marcas, sem o "-- "
create function pg_temp.desfazer(p_mig text) returns text language sql immutable as $f$
  select string_agg(substr(l, 6), E'\n' order by o)
    from (select l, o, sum(case when l like '-- DESFAZER-INICIO%' then 1 when l like '-- DESFAZER-FIM%' then -1 else 0 end) over (order by o) as dentro
            from unnest(string_to_array(replace(p_mig, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
   where dentro = 1 and l not like '-- DESFAZER-INICIO%'
$f$;

do $s$
declare
  v_res   jsonb := '[]'::jsonb;
  v_mig   text := coalesce(current_setting('agenda_teste.mig_semente_fase7d', true), '');
  v_fix   text := coalesce(current_setting('agenda_teste.fase7d', true), '');
  v_foto  text;
  v_foto2 text;
  v_resto text;
  v_t     text;
  v_j     jsonb;
  v_n     int;
  l       public.agenda_locais;
  cf      public.agenda_config;
  v_ate   int;
  v_perg  int;
begin
  if v_mig = '' then
    insert into _resultado values ('S1 a S6', true, 'PULADO: sem agenda_teste.mig_semente_fase7d (rode pela bancada)');
    return;
  end if;

  -- As marinas de produção (wf7dd_p7_marinas, 05/11), com as que a bancada não tem; a de teste, uma inativa e uma sem cidade, para ficar de fora
  update public.marinas set active = true, city = 'Itajaí', state = 'SC' where name in ('Marina Itajaí');
  update public.marinas set active = true, city = 'Balneário Camboriú', state = 'SC' where name = 'MP Motorhomes';
  insert into public.marinas (id, name, city, state, active, latitude, longitude)
  select gen_random_uuid(), m.n, m.c, m.u, m.a, m.la, m.lo
    from (values ('Marina Itajaí', 'Itajaí', 'SC', true, -26.9109230::numeric, -48.6515960::numeric),
                 ('MP Motorhomes', 'Balneário Camboriú', 'SC', true, null, null),
                 ('Kalmar Estaleiro', 'Itajaí', 'SC', true, null, null),
                 ('Tedesco Marina Garden Plaza', 'Balneário Camboriú', 'SC', true, -27.0061359, -48.6159906),
                 ('Iate Clube Caiobá', 'Guaratuba', 'PR', true, null, null),
                 ('Marina do Sol', 'Guaratuba', 'PR', true, -25.8690000, -48.5740000),
                 ('Ponta do Poço Marina Clube', 'Pontal do Paraná', 'PR', true, null, null),
                 ('Veleiros da Ilha', 'Florianópolis', 'SC', true, null, null),
                 ('Marina Teste Auditoria', 'Itajaí', 'SC', true, null, null),
                 ('Marina Fechada', 'Penha', 'SC', false, null, null),
                 ('Marina Sem Cidade', null, 'SC', true, null, null)) m(n, c, u, a, la, lo)
   where not exists (select 1 from public.marinas x where x.name = m.n);
  update public.marinas set active = false where name not in ('Marina Itajaí', 'MP Motorhomes', 'Kalmar Estaleiro', 'Tedesco Marina Garden Plaza', 'Iate Clube Caiobá', 'Marina do Sol',
                                                              'Ponta do Poço Marina Clube', 'Veleiros da Ilha', 'Marina Teste Auditoria', 'Marina Sem Cidade');
  update public.agenda_config
     set modo_local_calendario = 'desligado', modo_local_autorizacao = 'desligado', modo_bem = 'desligado', modo_patio = 'desligado', modo_viagem = 'desligado', modo_mesmo_local = 'desligado',
         onde_fica_desde = null where id;
  v_resto := pg_temp.resto_config();
  v_ate := (select count(*) from public.agenda_acoes);
  v_perg := (select count(*) from public.agenda_perguntas);

  execute v_mig;

  -- ── S1. Os locais ──
  v_t := (select string_agg(x.nome || ' (' || x.tipo || ')', ', ' order by x.nome collate "C") from public.agenda_locais x);
  v_res := pg_temp.ok(v_res, 'S1a 8 locais, os tipos da §5.9 (R6.5): a MP é o pátio da HBR, a Kalmar é estaleiro; sem a de teste, a inativa e a sem cidade',
                      (select count(*) from public.agenda_locais) = 8 and (select count(*) from public.agenda_locais where ativo) = 8
                      and v_t = 'Iate Clube Caiobá (marina), Kalmar Estaleiro (estaleiro), MP Motorhomes (patio_hbr), Marina Itajaí (marina), Marina do Sol (marina), Ponta do Poço Marina Clube (marina), Tedesco Marina Garden Plaza (marina), Veleiros da Ilha (marina)', v_t);
  select * into l from public.agenda_locais x where x.tipo = 'patio_hbr';
  v_res := pg_temp.ok(v_res, 'S1b o pátio: um só, deslocamento 0, sem vagas (só conta), em Balneário Camboriú, com a nota do dono (AG7-18)',
                      l.nome = 'MP Motorhomes' and l.deslocamento_min = 0 and l.vagas is null and l.municipio = 'Balneário Camboriú' and l.uf = 'SC'
                      and l.nota_dono = 'O espaço da HBR fica dentro do pátio da MP Motorhomes, em Balneário Camboriú (AG7-18). Quantos motorhomes cabem: a dizer.', to_jsonb(l)::text);
  v_res := pg_temp.ok(v_res, 'S1c nenhum pátio em Itajaí', not exists (select 1 from public.agenda_locais x where x.tipo like 'patio%' and x.municipio ilike 'Itaja%'), null);
  v_t := (select string_agg(format('%s=%s', x.nome, array_to_string(x.apelidos, ',')), ' | ' order by x.nome collate "C") from public.agenda_locais x);
  v_res := pg_temp.ok(v_res, 'S1d os apelidos da §6.5, com os da MP no limite do CHECK (R6.5)', v_t =
    'Iate Clube Caiobá=caioba,iate clube caioba | Kalmar Estaleiro=kalmar,estaleiro kalmar | MP Motorhomes=mp motorhomes,mp motorhome,mp motor home,patio,patio da hbr,oficina,na hbr,com voces | Marina Itajaí=marina de itajai,marina itajai | Marina do Sol=marina do sol | Ponta do Poço Marina Clube=ponta do poco | Tedesco Marina Garden Plaza=tedesco,garden plaza | Veleiros da Ilha=veleiros da ilha', v_t);
  v_res := pg_temp.ok(v_res, 'S1e as coordenadas e o município vêm da marina', exists (select 1 from public.agenda_locais x where x.nome = 'Tedesco Marina Garden Plaza' and x.latitude = -27.006136 and x.longitude = -48.615991),
                      null);

  -- ── S2. A nota ──
  select * into l from public.agenda_locais x where x.nome = 'Marina Itajaí';
  v_res := pg_temp.ok(v_res, 'S2a a Marina Itajaí, o regimento de 2024: as regras da §5.9, conferido_por pesquisa',
                      l.conferido_por = 'pesquisa' and l.conferido_em = date '2026-10-29' and l.abre = time '08:00' and l.fecha = time '18:00' and l.sabado = 'manha' and l.feriado = 'fecha'
                      and l.exige_autorizacao and l.autorizacao_texto = 'autorização escrita do dono do barco com nome e documento de quem vai e as datas'
                      and l.seguro_exigido and l.seguro_texto = 'seguro de responsabilidade civil com a marina como segurada adicional'
                      and l.taxa_texto = 'taxa de prestador na portaria de serviço' and l.tomada_max_w = 1200 and l.tem_garagem_seca and l.box_max_min = 60
                      and l.fonte_texto like 'Regimento Interno da Marina Itajaí, 2024 %contradizem sobre feriado.', to_jsonb(l)::text);
  v_res := pg_temp.ok(v_res, 'S2b pesquisa não é conferido: a regra é nota (AG7-14), e o histórico não ganha linha da semente',
                      not public._agenda_local_conferido(l.id, date '2026-11-07') and l.historico = '[]'::jsonb, null);
  select * into l from public.agenda_locais x where x.nome = 'Tedesco Marina Garden Plaza';
  v_res := pg_temp.ok(v_res, 'S2c a Tedesco: a garagem seca, pesquisa, sem outra regra', l.tem_garagem_seca and l.conferido_por = 'pesquisa' and l.conferido_em = date '2026-10-29' and l.exige_autorizacao is null
                      and l.abre is null and l.sabado is null and l.fonte_texto = 'Pesquisa de 29/10/2026: 3 hangares de até 4 andares.', to_jsonb(l)::text);
  v_res := pg_temp.ok(v_res, 'S2d as outras: só o cadastro',
                      not exists (select 1 from public.agenda_locais x
                                   where x.nome not in ('Marina Itajaí', 'Tedesco Marina Garden Plaza')
                                     and (x.conferido_por is not null or x.conferido_em is not null or x.abre is not null or x.sabado is not null or x.exige_autorizacao is not null
                                          or x.tem_garagem_seca is not null or x.seguro_exigido is not null or x.tomada_max_w is not null or x.fonte_texto is not null)), null);

  -- ── S3. Os modos e a trava ──
  select * into cf from public.agenda_config c where c.id;
  v_res := pg_temp.ok(v_res, 'S3a os 6 em sombra e onde_fica_desde = o dia do dado',
                      array[cf.modo_local_calendario, cf.modo_local_autorizacao, cf.modo_bem, cf.modo_patio, cf.modo_viagem, cf.modo_mesmo_local] = array_fill('sombra'::text, array[6])
                      and cf.onde_fica_desde = public._hoje_brt() and cf.atualizado_por is null, to_jsonb(cf)::text);
  v_res := pg_temp.ok(v_res, 'S3b o resto de agenda_config igual: cliente_tipos_ligados sem onde_fica', pg_temp.resto_config() = v_resto and not ('onde_fica' = any (cf.cliente_tipos_ligados)), null);
  v_res := pg_temp.ok(v_res, 'S3c o dado não escreve mais nada: nem ação nem pergunta', (select count(*) from public.agenda_acoes) = v_ate and (select count(*) from public.agenda_perguntas) = v_perg, null);

  -- ── S4. Idempotente ──
  update public.agenda_config set atualizado_em = timestamptz '2026-01-01 10:00-03' where id;   -- now() não anda dentro da transação
  v_foto := pg_temp.foto_locais();
  v_foto2 := pg_temp.foto_config();
  execute v_mig;
  v_res := pg_temp.ok(v_res, 'S4a de novo: nada muda, nem a hora', pg_temp.foto_locais() = v_foto and pg_temp.foto_config() = v_foto2, null);
  update public.agenda_config set modo_patio = 'ligado', modo_bem = 'desligado', onde_fica_desde = date '2026-11-02' where id;
  update public.agenda_locais set conferido_por = 'dono', conferido_em = date '2026-11-05', atualizado_por = null where nome = 'Marina Itajaí';
  v_foto := pg_temp.foto_locais();
  execute v_mig;
  select * into cf from public.agenda_config c where c.id;
  v_res := pg_temp.ok(v_res, 'S4b ligado não é rebaixado; desligado volta a sombra; onde_fica_desde gravada não muda (a trava do M11)', cf.modo_patio = 'ligado' and cf.modo_bem = 'sombra' and cf.onde_fica_desde = date '2026-11-02', to_jsonb(cf)::text);
  v_res := pg_temp.ok(v_res, 'S4c o que o dono conferiu não é tocado', pg_temp.foto_locais() = v_foto, null);
  update public.agenda_config set modo_patio = 'sombra' where id;
  update public.agenda_locais set conferido_por = 'pesquisa', conferido_em = date '2026-10-29' where nome = 'Marina Itajaí';

  -- ── S5. Com a semente ──
  if v_fix <> '' then
    v_res := pg_temp.ok(v_res, 'S5a o resolvedor: "pátio", "oficina" e "com vocês" são a MP',
                        public.agenda_resolver_local('pátio', date '2026-11-07') ->> 'nome' = 'MP Motorhomes' and public.agenda_resolver_local('oficina', date '2026-11-07') ->> 'nome' = 'MP Motorhomes'
                        and public.agenda_resolver_local('com vocês', date '2026-11-07') ->> 'nome' = 'MP Motorhomes' and public.agenda_resolver_local('caioba', date '2026-11-07') ->> 'nome' = 'Iate Clube Caiobá', null);
    v_t := public.agenda_ver(null, null, null, 'locais', null, null, false, date '2030-01-07') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'S5b o foco com a semente: 8 no cadastro, nenhum conferido, as 2 notas de pesquisa',
                        -- (correção O1) o foco geral mostra as OS abertas; o que importa aqui é o cadastro
                        v_t ~ 'Locais: 8 no cadastro; nenhum conferido por você\. Só como nota: Marina Itajaí pede autorização, pede seguro, no sábado só abre de manhã e tem garagem seca \(pesquisa\); Tedesco Marina Garden Plaza tem garagem seca \(pesquisa\)\.', v_t);
    update public.agenda_config set onde_fica_desde = date '2026-11-07' where id;
    v_j := public._agenda_saude_local(date '2026-11-07', timestamptz '2026-11-07 16:20-03');
    v_res := pg_temp.ok(v_res, 'S5c a saúde em teste: os zeros', (v_j ->> 'zeros_ok')::boolean and v_j #>> '{modos,mesmo_local}' = 'sombra', v_j::text);
  else
    v_res := pg_temp.ok(v_res, 'S5', true, 'PULADO: sem a fixture da 7d');
  end if;

  -- ── S6. O DESFAZER ──
  v_t := pg_temp.desfazer(v_mig);
  v_res := pg_temp.ok(v_res, 'S6a um comando só: dois UPDATE, nenhum DELETE', v_t like 'with modos as (%' and v_t !~* '\mdelete\M' and (select count(*) from regexp_matches(v_t, '\mupdate public\.', 'g')) = 2
                      and (length(v_t) - length(replace(v_t, ';', ''))) = 1, left(v_t, 200));
  v_n := (select count(*) from public.agenda_locais);
  update public.agenda_config set modo_viagem = 'ligado' where id;
  update public.agenda_locais set conferido_por = 'dono', conferido_em = date '2026-11-05' where nome = 'Kalmar Estaleiro';
  execute v_t into v_j;
  select * into cf from public.agenda_config c where c.id;
  v_res := pg_temp.ok(v_res, 'S6b teste volta a desligado, ligado fica, e onde_fica_desde = nula (para o M11)',
                      cf.modo_local_calendario = 'desligado' and cf.modo_bem = 'desligado' and cf.modo_mesmo_local = 'desligado' and cf.modo_viagem = 'ligado' and cf.onde_fica_desde is null, to_jsonb(cf)::text);
  v_res := pg_temp.ok(v_res, 'S6c as linhas ficam, inativas; a que o dono conferiu continua ativa',
                      (select count(*) from public.agenda_locais) = v_n and (select string_agg(x.nome, ',') from public.agenda_locais x where x.ativo) = 'Kalmar Estaleiro', null);
  v_res := pg_temp.ok(v_res, 'S6d o pátio inativo sai da cadeia: a OS volta a não saber', not exists (select 1 from public.agenda_locais x where x.tipo = 'patio_hbr' and x.ativo), null);

  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(pg_temp.ok(v_res, 'S quebrou', false, sqlstate || ': ' || sqlerrm));
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
