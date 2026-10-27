-- Prova dos textos da Agenda de Produção, Fase 5 (pacote P1): o contexto, os modelos M1–M10 escritos pelo banco, o que a
-- mensagem ao cliente nunca leva e a gravação do que foi dito ao cliente (migration 20261028100100).
-- bancada: depende de 20261028100100
--
--   X1 os 18 textos da §6.1 byte a byte com a fixture-fase5 (e o T5 de cada um: nada proibido, até 400 caracteres, nenhum
--      número de OS, nenhum "http")
--   X2 a assinatura só na 1ª mensagem (o M1 escolhe primeira/seguinte; os outros ganham a assinatura no começo; sem o dono,
--      "Aqui é da …"; a janela de um ano; a mensagem em teste não conta)
--   X3 o serviço padrão pelo tipo do bem, o gênero, o nome próprio, o local e o acesso conhecido
--   X4 _agenda_cliente_texto_proibido (17 que recusa, 12 que deixa)
--   X5 o dado que falta, o tipo e a variante que não existem: 22023, nunca texto pela metade
--   X6 o prometido: a 1ª grava o original e a 2ª não; a faixa; sem data nada; a OS sem linha de planejamento; o histórico
--      até 20; o botão antigo
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase5_textos.sql
--   X4 roda em qualquer lugar; o resto só na bancada (a fixture-fase5; fora dela, PULADO). Termina em ROLLBACK.
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

-- O texto, ou 'erro <estado>: <mensagem>'.
create function pg_temp.texto(p_tipo text, p_var text, p_os uuid, p_dados jsonb) returns text language plpgsql as $f$
begin
  return public._agenda_cliente_texto(p_tipo, p_var, p_os, p_dados, date '2026-10-30');
exception when others then
  return 'erro ' || sqlstate || ': ' || sqlerrm;
end $f$;

-- ── X4. O que a mensagem ao cliente nunca leva (sem fixture) ────────────────────────────────────────────
insert into _resultado
select format('X4 recusa %s: %s', x.motivo, left(x.texto, 40)), public._agenda_cliente_texto_proibido(x.texto) is not distinct from x.motivo,
       public._agenda_cliente_texto_proibido(x.texto)
  from (values
    ('Fica R$ 200 o serviço.', 'valor'),
    ('O valor fica igual.', 'valor'),
    ('O pagamento pode ser amanhã.', 'pagamento'),
    ('Pague quando puder.', 'pagamento'),
    ('Segue o boleto.', 'pagamento'),
    ('Me manda o pix.', 'pagamento'),
    ('A chave PIX é a de sempre.', 'pagamento'),
    ('A cobrança sai amanhã.', 'pagamento'),
    ('Consigo um desconto para você.', 'desconto'),
    ('A OS-00104 ficou pronta.', 'os'),
    ('O ORÇ-00083 foi aprovado.', 'os'),
    ('o orc-00083 foi aprovado.', 'os'),
    ('O número 00104 ficou pronto.', 'os'),
    ('Veja em http://exemplo.test', 'link'),
    ('Veja em www.exemplo.test', 'link'),
    ('Tudo certo 👍👍', 'emoji'),
    (repeat('a', 401), 'tamanho')
  ) as x(texto, motivo);

insert into _resultado
select format('X4 deixa: %s', coalesce(left(x.texto, 40), '(nulo)')), public._agenda_cliente_texto_proibido(x.texto) is null,
       public._agenda_cliente_texto_proibido(x.texto)
  from (values
    ('Podemos começar terça (03/11), à tarde?'),
    ('Tudo certo? 👍'),
    ('Responda SIM, ou me diga um dia melhor.'),
    ('Se preferir não receber estas mensagens, é só responder PARAR.'),
    ('Na Marina de Itajaí, vaga 12.'),
    ('O serviço fica para 03/11/2026.'),
    ('Os barcos da marina.'),
    ('A peça ainda não chegou e agora está prevista para quarta (11/11).'),
    ('Desculpe o transtorno.'),
    ('Onde o seu motorhome vai estar, e a chave fica com quem?'),
    (repeat('a', 400)),
    (null)
  ) as x(texto);

insert into _resultado
select 'X4z _agenda_cliente_texto_proibido é IMMUTABLE, sem definer',
       p.provolatile = 'i' and not p.prosecdef, null
  from pg_proc p where p.oid = 'public._agenda_cliente_texto_proibido(text)'::regprocedure;

-- ── X1, X2, X3, X5, X6 (a fixture-fase5) ────────────────────────────────────────────────────────────────
do $x$
declare
  v_res jsonb := '[]'::jsonb;
  c_fla  constant uuid := '05000000-0000-4000-8000-000000000104';
  c_len  constant uuid := '05000000-0000-4000-8000-000000000074';
  c_nel  constant uuid := '05000000-0000-4000-8000-000000000112';
  c_ven  constant uuid := '05000000-0000-4000-8000-000000000069';
  c_gia  constant uuid := '05000000-0000-4000-8000-000000000100';
  c_luc  constant uuid := '05000000-0000-4000-8000-000000000122';
  c_rob  constant uuid := '05000000-0000-4000-8000-000000000121';
  c_dono_os constant uuid := '05000000-0000-4000-8000-000000000123';
  c_agora constant timestamptz := timestamptz '2026-10-30 10:00-03';
  r record;
  v text;
  j jsonb;
  p public.os_planejamento;
  v_ok boolean;
  v_det text;
  i int;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('X1–X6 os textos e o prometido (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase5');

    -- ── X0. Os auxiliares de tempo da fixture (spec §8.1) ──
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    v_res := pg_temp.ok(v_res, 'X0 a fixture: pg_temp.agora(''2026-10-30 10:00'') é 10:00 de Brasília e _hoje_brt() segue agenda_teste.hoje',
      pg_temp.agora('2026-10-30 10:00') = timestamptz '2026-10-30 10:00-03' and public._hoje_brt() = date '2026-10-30'
      and public._agenda_cliente_texto('confirmar', 'seguinte', c_fla, '{}') like 'Flávio, conseguimos encaixar %');
    perform set_config('agenda_teste.hoje', '', true);

    -- ── X1. Os 18 textos da §6.1 byte a byte ──
    create temp table _x1 (n int, tipo text, variante text, os uuid, dados jsonb, esperado text) on commit drop;
    insert into _x1 values
      (1, 'confirmar', 'primeira', c_fla, '{}',
       'Olá, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. Conseguimos encaixar a instalação do compressor para terça (03/11), à tarde, com previsão de 2 dias de trabalho. Pode ser? Responda SIM para confirmar, ou me diga um dia melhor. A partir de agora te mando por aqui as novidades do serviço.'),
      (2, 'confirmar', 'seguinte', c_fla, '{}',
       'Flávio, conseguimos encaixar a instalação do compressor para terça (03/11), à tarde, com previsão de 2 dias. Pode ser? Responda SIM ou me diga um dia melhor.'),
      (3, 'confirmar', 'unico', c_len, '{"primeira": false}',
       'Lenine, o serviço no Brisa fica para sexta (06/11), pela manhã, na Marina de Itajaí. Pode ser? Responda SIM, ou me diga se algo mudou.'),
      (4, 'vespera', null, c_len, '{"primeira": false, "envio": "2026-11-05"}',
       'Bom dia, Lenine! Amanhã chegamos pela manhã para o serviço no Brisa, na Marina de Itajaí. Está tudo certo para recebermos? Responda SIM, ou me avise se algo mudou.'),
      (5, 'acesso', null, c_fla, '{"primeira": false, "envio": "2026-10-31"}',
       'Bom dia, Flávio! Na terça (03/11) chegamos à tarde para a instalação do compressor. Para não perdermos a viagem: onde o seu motorhome vai estar, e a chave fica com quem? Pode responder por aqui mesmo, até por áudio.'),
      (6, 'material_chegou', null, c_fla, '{"primeira": false}',
       'Boa notícia, Flávio: o material da instalação do compressor chegou e já foi conferido. Podemos começar terça (03/11), à tarde? Responda SIM, ou me diga um dia melhor.'),
      (7, 'pode_atrasar', 'peca', c_nel, '{"peca_de": "2026-11-11", "peca_ate": "2026-11-11", "faixa_de": "2026-11-12", "faixa_ate": "2026-11-13"}',
       'Nelson, quero te avisar com antecedência: a peça do serviço no seu veleiro ainda não chegou e agora está prevista para quarta (11/11). Por isso, o serviço no seu veleiro, que estava para quinta (05/11), deve ficar entre quinta (12/11) e sexta (13/11). Te confirmo a data assim que a peça chegar. Se isso atrapalhar algum plano seu, me diga.'),
      (8, 'pode_atrasar', 'execucao', c_ven, '{"primeira": false, "faixa_de": "2026-11-05", "faixa_ate": "2026-11-06"}',
       'Vanderlei, o serviço no Mar Azul está levando mais tempo do que eu estimei. A nova previsão para terminar é entre quinta (05/11) e sexta (06/11). Qualquer dúvida, me chama.'),
      (9, 'pode_atrasar', 'remarcado', c_ven, '{"primeira": false, "dia_dito": "2026-10-29"}',
       'Vanderlei, o serviço no Mar Azul, que estava para quinta (29/10), precisou passar para terça (03/11), o dia todo. Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.'),
      (10, 'nova_data', null, c_fla, '{"primeira": false}',
       'Flávio, agora com data firme: a instalação do compressor fica para terça (03/11), à tarde. Desculpe pela mudança e obrigado pela paciência. Responda SIM para confirmar, ou me diga se precisa de outro dia.'),
      (11, 'andamento', 'primeiro_dia', c_fla, '{"primeira": false}',
       'Flávio, começamos hoje a instalação do compressor. Seguimos com a previsão de terminar quarta (04/11).'),
      (12, 'andamento', 'semanal', c_ven, '{"primeira": false, "n_feitos": 1}',
       'Vanderlei, seguimos com o serviço no Mar Azul: 1 de 3 dias feitos, previsão de terminar quinta (05/11).'),
      (13, 'pronto', null, c_luc, '{"primeira": false}',
       'Lucenira, a troca das baterias está concluída. Quando fica bom para combinarmos a entrega?'),
      (14, 'pronto_lembrete', null, c_luc, '{"primeira": false}',
       'Lucenira, só para combinarmos a entrega da sua lancha: qual dia fica bom pra você?'),
      (15, 'pos_servico', null, c_rob, '{"primeira": false}',
       'Robson, tudo certo com o serviço no seu motorhome? Já deu para usar? Se algo não estiver como esperado, me responde aqui que a gente resolve. Se preferir não receber estas mensagens, é só responder PARAR.'),
      (16, 'mudanca_no_dia', 'clima', c_fla, '{"primeira": false, "quando": "amanhã"}',
       'Bom dia, Flávio. Com a chuva de amanhã não dá para trabalhar no seu motorhome com segurança. Podemos passar para terça (03/11), à tarde? Responda SIM ou me diga outro dia.'),
      (17, 'mudanca_no_dia', 'equipe', c_fla, '{"primeira": false, "quando": "hoje"}',
       'Flávio, tive um imprevisto com a equipe e não vamos conseguir ir hoje. Desculpe o transtorno. Podemos ir terça (03/11), à tarde? Responda SIM ou me diga outro dia.'),
      (18, 'mudanca_no_dia', 'geral', c_fla, '{"primeira": false, "quando": "amanhã"}',
       'Flávio, tive um imprevisto e não vamos conseguir ir amanhã. Desculpe o transtorno. Podemos ir terça (03/11), à tarde? Responda SIM ou me diga outro dia.');

    for r in select * from _x1 order by n loop
      v := pg_temp.texto(r.tipo, r.variante, r.os, r.dados);
      v_res := pg_temp.ok(v_res, format('X1 %s %s%s', lpad(r.n::text, 2, '0'), r.tipo, coalesce(' ' || r.variante, '')),
                          v = r.esperado, case when v is distinct from r.esperado then v end);
      v_res := pg_temp.ok(v_res, format('X1t %s %s: nada proibido, até 400, sem número de OS, sem http', lpad(r.n::text, 2, '0'), r.tipo),
                          public._agenda_cliente_texto_proibido(v) is null and char_length(v) <= 400 and v !~ '\d{5}' and v !~* 'http'
                          and v !~* '\m(os|or[cç])-',
                          format('%s caracteres; proibido %s', char_length(v), public._agenda_cliente_texto_proibido(v)));
    end loop;
    v_res := pg_temp.ok(v_res, 'X1z os 11 tipos e as 18 variantes da §6.1 têm caso',
      (select count(distinct tipo) = 11 and count(*) = 18 from _x1));

    -- ── X2. A assinatura só na 1ª mensagem ──
    v_res := pg_temp.ok(v_res, 'X2a o M1 sem variante, para quem nunca recebeu: a primeira (com a assinatura)',
      pg_temp.texto('confirmar', null, c_fla, '{}') = (select esperado from _x1 where n = 1));
    v := pg_temp.texto('acesso', null, c_fla, '{"envio": "2026-10-31"}');
    v_res := pg_temp.ok(v_res, 'X2b o M4 da 1ª vez: a assinatura logo depois do "Bom dia"',
      v = 'Bom dia, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. Na terça (03/11) chegamos à tarde para a instalação do compressor. Para não perdermos a viagem: onde o seu motorhome vai estar, e a chave fica com quem? Pode responder por aqui mesmo, até por áudio.',
      v);
    v := pg_temp.texto('pronto', null, c_luc, '{}');
    v_res := pg_temp.ok(v_res, 'X2c o M8 da 1ª vez: "Olá, Lucenira! Aqui é o … ." e o resto com maiúscula',
      v = 'Olá, Lucenira! Aqui é o Gustavo, da HBR Marine Solutions. A troca das baterias está concluída. Quando fica bom para combinarmos a entrega?', v);
    v := pg_temp.texto('material_chegou', null, c_fla, '{}');
    v_res := pg_temp.ok(v_res, 'X2d o M3 da 1ª vez: "Olá, Flávio! Aqui é o … . Boa notícia: …"',
      v = 'Olá, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. Boa notícia: o material da instalação do compressor chegou e já foi conferido. Podemos começar terça (03/11), à tarde? Responda SIM, ou me diga um dia melhor.', v);
    v := pg_temp.texto('mudanca_no_dia', 'clima', c_fla, '{"quando": "amanhã"}');
    v_res := pg_temp.ok(v_res, 'X2e o M10 (chuva) da 1ª vez: "Bom dia, Flávio. Aqui é o … ."',
      v = 'Bom dia, Flávio. Aqui é o Gustavo, da HBR Marine Solutions. Com a chuva de amanhã não dá para trabalhar no seu motorhome com segurança. Podemos passar para terça (03/11), à tarde? Responda SIM ou me diga outro dia.', v);
    v_res := pg_temp.ok(v_res, 'X2f o M1 seguinte nunca assina, nem na 1ª vez; o Nelson (que recebeu em 22/10) não é 1ª vez',
      pg_temp.texto('confirmar', 'seguinte', c_fla, '{}') = (select esperado from _x1 where n = 2)
      and not (public._agenda_cliente_contexto(c_nel, date '2026-10-30') ->> 'primeira')::boolean
      and (public._agenda_cliente_contexto(c_fla, date '2026-10-30') ->> 'primeira')::boolean);

    -- sem o dono (o sócio inativo): "Aqui é da …"; sem o nome da empresa: "HBR Marine"
    update public.payees set active = false where kind = 'socio';
    v := pg_temp.texto('confirmar', null, c_fla, '{}');
    v_ok := v like 'Olá, Flávio! Aqui é da HBR Marine Solutions. Conseguimos encaixar %';
    delete from public.app_settings where key = 'company_name';
    v := pg_temp.texto('pronto', null, c_luc, '{}');
    v_res := pg_temp.ok(v_res, 'X2g sem o dono: "Aqui é da HBR Marine Solutions."; sem o nome da empresa: "Aqui é da HBR Marine."',
      v_ok and v = 'Olá, Lucenira! Aqui é da HBR Marine. A troca das baterias está concluída. Quando fica bom para combinarmos a entrega?', v);
    update public.payees set active = true where kind = 'socio';
    insert into public.app_settings (key, value) values ('company_name', 'HBR Marine Solutions')
      on conflict (key) do update set value = excluded.value;

    -- a janela de um ano e a mensagem em teste (sombra, registrada) que não conta
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                 aprovacao, dedupe_key)
    values ('c1000000-0000-4000-8000-000000000004', c_fla, 'confirmar', 'rodada', 'sombra', 'Flávio, em teste.', c_agora,
            c_agora + interval '9 hours', 'livre', 'agenda-cliente:x2:sombra');
    v_ok := (public._agenda_cliente_contexto(c_fla, date '2026-10-30') ->> 'primeira')::boolean;
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                 aprovacao, aprovada_em, estado, enviada_em, dedupe_key)
    values ('c1000000-0000-4000-8000-000000000004', c_fla, 'pronto', 'rodada', 'ligado', 'Flávio, o serviço está concluído.',
            timestamptz '2025-10-30 09:00-03', timestamptz '2025-10-30 19:00-03', 'aprovada', timestamptz '2025-10-29 17:00-03',
            'enviada', timestamptz '2025-10-30 09:00-03', 'agenda-cliente:x2:ano');
    v_ok := v_ok and (public._agenda_cliente_contexto(c_fla, date '2026-10-30') ->> 'primeira')::boolean;
    v_res := pg_temp.ok(v_res, 'X2h a mensagem em teste não conta, nem a enviada há um ano (30/10/2025): continua a 1ª vez', v_ok);
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                 aprovacao, aprovada_em, estado, enviada_em, dedupe_key)
    values ('c1000000-0000-4000-8000-000000000004', c_fla, 'pronto', 'rodada', 'ligado', 'Flávio, o serviço está concluído.',
            timestamptz '2025-10-31 09:00-03', timestamptz '2025-10-31 19:00-03', 'aprovada', timestamptz '2025-10-30 17:00-03',
            'enviada', timestamptz '2025-10-31 09:00-03', 'agenda-cliente:x2:ano2');
    v_res := pg_temp.ok(v_res, 'X2i depois de uma enviada há menos de um ano (31/10/2025): o M1 sem variante é o seguinte, sem assinatura',
      not (public._agenda_cliente_contexto(c_fla, date '2026-10-30') ->> 'primeira')::boolean
      and pg_temp.texto('confirmar', null, c_fla, '{}') = (select esperado from _x1 where n = 2)
      and pg_temp.texto('acesso', null, c_fla, '{"envio": "2026-10-31"}') = (select esperado from _x1 where n = 5));

    -- ── X3. O serviço padrão pelo tipo do bem, o gênero, o nome, o local e o acesso ──
    j := public._agenda_cliente_contexto(c_gia, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'X3a Giancarlo (Motorhome sem nome próprio): "o serviço no seu motorhome"',
      j ->> 'servico' = 'o serviço no seu motorhome' and j ->> 'bem' = 'seu motorhome' and j ->> 'o_bem' = 'o seu motorhome'
      and j ->> 'do_servico' = 'do serviço no seu motorhome' and j ->> 'local' = '' and j ->> 'nome' = 'Giancarlo', j::text);
    j := public._agenda_cliente_contexto(c_ven, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'X3b Vanderlei (a lancha Mar Azul): o nome próprio — "o serviço no Mar Azul"',
      j ->> 'servico' = 'o serviço no Mar Azul' and j ->> 'bem' = 'o Mar Azul' and j ->> 'do_bem' = 'do Mar Azul'
      and j ->> 'janela_texto' = 'o dia todo' and (j ->> 'n_dias')::int = 3 and j ->> 'nivel_material' = 'D', j::text);
    j := public._agenda_cliente_contexto(c_nel, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'X3c Nelson (Veleiro): "seu veleiro"; sem plano: sem dia; o prometido de 22/10',
      j ->> 'bem' = 'seu veleiro' and j ->> 'dia' is null and j #>> '{prometido,ate}' = '2026-11-05'
      and j #>> '{prometido,fonte}' = 'mensagem' and j ->> 'material_estado' = 'sem_previsao', j::text);
    j := public._agenda_cliente_contexto(c_luc, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'X3d Lucenira (Lancha): feminino — "da sua lancha"; o serviço dela com artigo feminino; a marina e a vaga',
      j ->> 'bem' = 'sua lancha' and j ->> 'o_bem' = 'a sua lancha' and j ->> 'no_bem' = 'na sua lancha'
      and j ->> 'do_bem' = 'da sua lancha' and (j ->> 'bem_feminino')::boolean
      and j ->> 'servico' = 'a troca das baterias' and j ->> 'do_servico' = 'da troca das baterias'
      and j ->> 'local' = ', na Marina de Itajaí, vaga 12', j::text);
    update public.os_planejamento set servico_cliente = null where service_order_id = c_luc;
    j := public._agenda_cliente_contexto(c_luc, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'X3e sem o serviço dito: "o serviço na sua lancha"',
      j ->> 'servico' = 'o serviço na sua lancha' and pg_temp.texto('pronto', null, c_luc, '{"primeira": false}')
        = 'Lucenira, o serviço na sua lancha está concluído. Quando fica bom para combinarmos a entrega?', j ->> 'servico');

    -- o nome que começa pelo tipo, o tipo nulo, o catamarã, o artigo do serviço (plural e sem artigo)
    update public.vessels set name = 'Lancha Azimut 42' where id = 'f1000000-0000-4000-8000-000000000012';
    v_ok := public._agenda_cliente_contexto(c_luc, date '2026-10-30') ->> 'bem' = 'sua lancha';
    update public.vessels set name = 'Veleiro', asset_type = null where id = 'f1000000-0000-4000-8000-000000000012';
    v_ok := v_ok and public._agenda_cliente_contexto(c_luc, date '2026-10-30') ->> 'bem' = 'seu veleiro';
    update public.vessels set name = 'Catamarã', asset_type = 'Catamarã' where id = 'f1000000-0000-4000-8000-000000000012';
    v_ok := v_ok and public._agenda_cliente_contexto(c_luc, date '2026-10-30') ->> 'no_bem' = 'no seu catamarã';
    v_res := pg_temp.ok(v_res, 'X3f o nome que começa pelo tipo ("Lancha Azimut 42") é o tipo; sem tipo, o nome de uma palavra é o tipo; "seu catamarã"', v_ok);
    update public.os_planejamento set servico_cliente = 'As baterias novas' where service_order_id = c_luc;
    v := pg_temp.texto('pronto', null, c_luc, '{"primeira": false}');
    v_ok := v = 'Lucenira, as baterias novas estão concluídas. Quando fica bom para combinarmos a entrega?';
    update public.os_planejamento set servico_cliente = 'Os reparos do casco' where service_order_id = c_luc;
    v_ok := v_ok and pg_temp.texto('pronto', null, c_luc, '{"primeira": false}')
                     = 'Lucenira, os reparos do casco estão concluídos. Quando fica bom para combinarmos a entrega?';
    update public.os_planejamento set servico_cliente = 'troca do inversor' where service_order_id = c_luc;
    v_ok := v_ok and public._agenda_cliente_contexto(c_luc, date '2026-10-30') ->> 'do_servico' = 'de troca do inversor'
            and pg_temp.texto('pronto', null, c_luc, '{"primeira": false}')
                = 'Lucenira, troca do inversor está concluído. Quando fica bom para combinarmos a entrega?';
    v_res := pg_temp.ok(v_res, 'X3g o artigo do serviço: "As baterias novas" → "as baterias novas estão concluídas"; "os reparos … concluídos"; sem artigo, "de troca do inversor"', v_ok, v);

    -- o local: a marina que não começa por "marina", a vaga que não é número, a cidade do cliente (a quebrada fica de fora)
    update public.marinas set name = 'Kalmar Estaleiro' where id = 'ee000000-0000-4000-8000-000000000001';
    update public.vessels set current_dock_position = 'Píer B' where id = 'f1000000-0000-4000-8000-000000000012';
    v_ok := public._agenda_cliente_contexto(c_luc, date '2026-10-30') ->> 'local' = ', na marina Kalmar Estaleiro, Píer B';
    v_ok := v_ok and public._agenda_cliente_contexto(c_dono_os, date '2026-10-30') ->> 'local' = ', em Itajaí';
    update public.clients set city = 'NAVEGANTES' where id = 'c1000000-0000-4000-8000-000000000013';
    v_ok := v_ok and public._agenda_cliente_contexto(c_dono_os, date '2026-10-30') ->> 'local' = ', em Navegantes';
    update public.clients set city = 'Itaja' || chr(65533) where id = 'c1000000-0000-4000-8000-000000000013';
    v_ok := v_ok and public._agenda_cliente_contexto(c_dono_os, date '2026-10-30') ->> 'local' = '';
    v_res := pg_temp.ok(v_res, 'X3h o local: ", na marina Kalmar Estaleiro, Píer B"; sem marina, a cidade do cliente (", em Itajaí"; a maiúscula vira "Navegantes"; a quebrada fica de fora)', v_ok);

    -- o acesso conhecido: o da OS, o do bem, o da marina, o dito há 30 dias (vale) e há 100 (venceu)
    v_ok := not (public._agenda_cliente_contexto(c_fla, date '2026-10-30') ->> 'acesso_conhecido')::boolean;
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set site_access = 'Chave com o caseiro.' where id = c_fla;
    v_ok := v_ok and (public._agenda_cliente_contexto(c_fla, date '2026-10-30') ->> 'acesso_conhecido')::boolean;
    update public.service_orders set site_access = null where id = c_fla;
    perform set_config('agenda.porta', 'off', true);
    update public.vessels set access_notes = 'Na garagem dos fundos.' where id = 'f1000000-0000-4000-8000-000000000004';
    v_ok := v_ok and (public._agenda_cliente_contexto(c_fla, date '2026-10-30') ->> 'acesso_conhecido')::boolean;
    update public.vessels set access_notes = null where id = 'f1000000-0000-4000-8000-000000000004';
    update public.os_planejamento set acesso_ok_em = timestamptz '2026-09-30 10:00-03' where service_order_id = c_fla;
    v_ok := v_ok and (public._agenda_cliente_contexto(c_fla, date '2026-10-30') ->> 'acesso_conhecido')::boolean;
    update public.os_planejamento set acesso_ok_em = timestamptz '2026-07-22 10:00-03' where service_order_id = c_fla;
    v_ok := v_ok and not (public._agenda_cliente_contexto(c_fla, date '2026-10-30') ->> 'acesso_conhecido')::boolean;
    update public.os_planejamento set acesso_ok_em = null where service_order_id = c_fla;
    v_ok := v_ok and (public._agenda_cliente_contexto(c_len, date '2026-10-30') ->> 'acesso_conhecido') = 'false';
    update public.marinas set access_notes = 'Portaria 24 h; avisar o nome.' where id = 'ee000000-0000-4000-8000-000000000001';
    v_ok := v_ok and (public._agenda_cliente_contexto(c_len, date '2026-10-30') ->> 'acesso_conhecido')::boolean;
    v_res := pg_temp.ok(v_res, 'X3i o acesso conhecido: o da OS, o do bem, o da marina e o dito há 30 dias; o de 100 dias venceu', v_ok);

    -- o telefone: o WhatsApp do cliente; sem número, nulo; o do dono (cadastrado como cliente), nulo
    v_res := pg_temp.ok(v_res, 'X3j o telefone: o WhatsApp do Flávio (55…); o Lenine sem número; o dono como cliente, nunca',
      public._agenda_cliente_telefone('c1000000-0000-4000-8000-000000000004') = '5547900000304'
      and public._agenda_cliente_telefone('c1000000-0000-4000-8000-000000000002') is null
      and public._agenda_cliente_telefone('c1000000-0000-4000-8000-000000000013') is null
      and not (public._agenda_cliente_contexto(c_dono_os, date '2026-10-30') ->> 'telefone_ok')::boolean
      and not (public._agenda_cliente_contexto(c_len, date '2026-10-30') ->> 'telefone_ok')::boolean
      and (public._agenda_cliente_contexto(c_fla, date '2026-10-30') ->> 'telefone_ok')::boolean);
    update public.clients set whatsapp = null, phone = '(47) 99000-0304' where id = 'c1000000-0000-4000-8000-000000000004';
    v_ok := public._agenda_cliente_telefone('c1000000-0000-4000-8000-000000000004') = '5547990000304';
    update public.clients set phone = '4799000030' where id = 'c1000000-0000-4000-8000-000000000004';
    v_ok := v_ok and public._agenda_cliente_telefone('c1000000-0000-4000-8000-000000000004') = '554799000030';
    update public.clients set phone = '4479900003041' where id = 'c1000000-0000-4000-8000-000000000004';
    v_ok := v_ok and public._agenda_cliente_telefone('c1000000-0000-4000-8000-000000000004') is null;
    update public.clients set phone = '5547900000001' where id = 'c1000000-0000-4000-8000-000000000004';   -- o do Roberto
    v_ok := v_ok and public._agenda_cliente_telefone('c1000000-0000-4000-8000-000000000004') is null;
    v_res := pg_temp.ok(v_res, 'X3k o telefone do cadastro: 11 e 10 dígitos ganham o 55; 13 sem 55 não vale; o de quem recebe diária (o Roberto), nunca', v_ok);
    update public.clients set whatsapp = '5547900000304', phone = null where id = 'c1000000-0000-4000-8000-000000000004';

    -- ── X5. O dado que falta: 22023 ──
    v_ok := true;
    v_det := '';
    for r in select * from (values
        ('cobranca', null, c_fla, '{}', 'erro 22023: Tipo de mensagem ao cliente desconhecido: cobranca.'),
        ('confirmar', 'outra', c_fla, '{}', 'erro 22023: Variante outra não existe na mensagem confirmar.'),
        ('pode_atrasar', null, c_nel, '{}', 'erro 22023: Variante (nenhuma) não existe na mensagem pode_atrasar.'),
        ('vespera', 'unico', c_fla, '{}', 'erro 22023: Variante unico não existe na mensagem vespera.'),
        ('confirmar', null, c_nel, '{}', 'erro 22023: Falta o dia para a mensagem confirmar ao cliente.'),
        ('vespera', null, c_fla, '{"dia": "2026-11-20"}', 'erro 22023: Falta a parte do dia (as alocações do dia) para a mensagem vespera ao cliente.'),
        ('pode_atrasar', 'peca', c_nel, '{"faixa_de": "2026-11-12"}', 'erro 22023: Falta a previsão da peça para a mensagem pode_atrasar ao cliente.'),
        ('pode_atrasar', 'peca', c_nel, '{"peca_de": "2026-11-11"}', 'erro 22023: Falta a faixa nova para a mensagem pode_atrasar ao cliente.'),
        ('pode_atrasar', 'peca', c_ven, '{"peca_de": "2026-11-11", "faixa_de": "2026-11-12"}', 'erro 22023: Falta o dia dito ao cliente para a mensagem pode_atrasar ao cliente.'),
        ('pode_atrasar', 'execucao', c_ven, '{}', 'erro 22023: Falta a faixa nova para a mensagem pode_atrasar ao cliente.'),
        ('pode_atrasar', 'remarcado', c_ven, '{}', 'erro 22023: Falta o dia dito ao cliente para a mensagem pode_atrasar ao cliente.'),
        ('andamento', 'semanal', c_ven, '{}', 'erro 22023: Falta os dias feitos e o total para a mensagem andamento ao cliente.'),
        ('andamento', 'primeiro_dia', c_nel, '{}', 'erro 22023: Falta o fim previsto para a mensagem andamento ao cliente.'),
        ('mudanca_no_dia', 'clima', c_fla, '{}', 'erro 22023: Falta o quando (hoje ou amanhã) para a mensagem mudanca_no_dia ao cliente.'),
        ('mudanca_no_dia', 'equipe', c_fla, '{"quando": "ontem"}', 'erro 22023: Falta o quando (hoje ou amanhã) para a mensagem mudanca_no_dia ao cliente.'),
        ('material_chegou', null, c_gia, '{}', 'erro 22023: Falta o dia para a mensagem material_chegou ao cliente.'),
        ('pronto', null, 'd5000000-0000-4000-8000-0000000000ff', '{}', 'erro 22023: OS não encontrada para a mensagem ao cliente.')
      ) as t(tipo, var, os, dados, espera)
    loop
      v := pg_temp.texto(r.tipo, r.var, r.os, r.dados::jsonb);
      if v is distinct from r.espera then
        v_ok := false;
        v_det := v_det || format('[%s %s: %s] ', r.tipo, coalesce(r.var, '-'), v);
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'X5 o tipo e a variante que não existem e cada dado que falta: 22023 com o que falta (17 casos)', v_ok, nullif(v_det, ''));

    -- ── X6. O prometido ──
    -- (a) 1ª promessa do Flávio: o M1 de ter 03/11 (fim qua 04/11) saiu
    insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, dia_alvo, prometido_tipo,
                                                 modo, texto, base, enviar_em, valida_ate, aprovacao, aprovada_em, estado,
                                                 enviada_em, dedupe_key)
    values ('d5000000-0000-4000-8000-0000000006a1', 'c1000000-0000-4000-8000-000000000004', c_fla, 'confirmar', 'primeira', 'rodada',
            date '2026-11-03', 'firme', 'ligado', (select esperado from _x1 where n = 1),
            '{"dia_alvo": "2026-11-03", "fim": "2026-11-04"}', timestamptz '2026-10-31 09:00-03', timestamptz '2026-10-31 13:00-03',
            'aprovada', timestamptz '2026-10-30 17:40-03', 'enviada', timestamptz '2026-10-31 09:00:40-03',
            'agenda-cliente:confirmar:' || c_fla || ':2026-11-03');
    j := public._agenda_cliente_prometer('d5000000-0000-4000-8000-0000000006a1', timestamptz '2026-10-31 09:00:40-03');
    select * into p from public.os_planejamento where service_order_id = c_fla;
    v_res := pg_temp.ok(v_res, 'X6a a 1ª promessa: firme de ter 03/11 a qua 04/11, o original = qua 04/11, fonte mensagem, a mensagem e a hora',
      (j ->> 'gravou')::boolean and (j ->> 'primeira_promessa')::boolean
      and p.prometido_tipo = 'firme' and p.prometido_de = date '2026-11-03' and p.prometido_ate = date '2026-11-04'
      and p.prometido_original_ate = date '2026-11-04' and p.prometido_fonte = 'mensagem'
      and p.prometido_mensagem_id = 'd5000000-0000-4000-8000-0000000006a1'
      and p.prometido_em = timestamptz '2026-10-31 09:00:40-03' and p.atualizado_em = timestamptz '2026-10-31 09:00:40-03'
      and p.historico -> -1 -> 'depois' = '{"prometido_tipo": "firme", "prometido_de": "2026-11-03", "prometido_ate": "2026-11-04", "prometido_fonte": "mensagem"}'::jsonb
      and p.historico -> -1 -> 'antes' ->> 'prometido_ate' is null
      and p.historico -> -1 ->> 'em' = '2026-10-31'
      and p.historico -> -1 ->> 'trecho' like 'mensagem ao cliente (M1): Olá, Flávio!%'
      -- o resto da linha não muda (o serviço dito e os dias que o dono disse)
      and p.servico_cliente = 'a instalação do compressor' and p.dias = 1,
      to_jsonb(p)::text);
    -- (b) a 2ª (o M7 de qui 05 a sex 06/11): o prometido muda, o original não
    insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, origem, dia_alvo, prometido_tipo, modo, texto,
                                                 base, enviar_em, valida_ate, aprovacao, aprovada_em, estado, enviada_em, dedupe_key)
    values ('d5000000-0000-4000-8000-0000000006a2', 'c1000000-0000-4000-8000-000000000004', c_fla, 'nova_data', 'rodada',
            date '2026-11-05', 'firme', 'ligado', 'Flávio, agora com data firme: …', '{"dia_alvo": "2026-11-05", "fim": "2026-11-06"}',
            timestamptz '2026-11-03 09:00-03', timestamptz '2026-11-04 19:00-03', 'aprovada', timestamptz '2026-11-03 08:00-03',
            'enviada', timestamptz '2026-11-03 09:01-03', 'agenda-cliente:nova_data:' || c_fla || ':2026-11-05');
    j := public._agenda_cliente_prometer('d5000000-0000-4000-8000-0000000006a2', timestamptz '2026-11-03 09:01-03');
    select * into p from public.os_planejamento where service_order_id = c_fla;
    v_res := pg_temp.ok(v_res, 'X6b a 2ª promessa: qui 05 a sex 06/11; o original fica qua 04/11; o histórico guarda o antes',
      not (j ->> 'primeira_promessa')::boolean
      and p.prometido_de = date '2026-11-05' and p.prometido_ate = date '2026-11-06' and p.prometido_original_ate = date '2026-11-04'
      and p.prometido_mensagem_id = 'd5000000-0000-4000-8000-0000000006a2'
      and p.historico -> -1 -> 'antes' ->> 'prometido_ate' = '2026-11-04', to_jsonb(p)::text);
    -- (c) a faixa (o M6 da peça): de e até são a faixa
    insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de, faixa_ate,
                                                 prometido_tipo, modo, texto, enviar_em, valida_ate, aprovacao, aprovada_em, estado,
                                                 enviada_em, dedupe_key)
    values ('d5000000-0000-4000-8000-0000000006a3', 'c1000000-0000-4000-8000-000000000005', c_nel, 'pode_atrasar', 'peca', 'rodada',
            date '2026-11-12', date '2026-11-12', date '2026-11-13', 'condicional', 'ligado', (select esperado from _x1 where n = 7),
            timestamptz '2026-10-31 09:00-03', timestamptz '2026-11-05 19:00-03', 'aprovada', timestamptz '2026-10-30 17:40-03',
            'enviada', timestamptz '2026-10-31 09:00:40-03', 'agenda-cliente:pode_atrasar:' || c_nel || ':2026-11-12');
    j := public._agenda_cliente_prometer('d5000000-0000-4000-8000-0000000006a3', timestamptz '2026-10-31 09:00:40-03');
    select * into p from public.os_planejamento where service_order_id = c_nel;
    v_res := pg_temp.ok(v_res, 'X6c a faixa do M6 (condicional): de qui 12 a sex 13/11; o original do Nelson continua qui 05/11; o prazo do cliente fica',
      p.prometido_tipo = 'condicional' and p.prometido_de = date '2026-11-12' and p.prometido_ate = date '2026-11-13'
      and p.prometido_original_ate = date '2026-11-05' and p.precisa_ate = date '2026-11-05', to_jsonb(p)::text);
    -- (d) a mensagem sem data não grava; (e) a que não existe também não
    insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                 aprovacao, aprovada_em, estado, enviada_em, dedupe_key)
    values ('d5000000-0000-4000-8000-0000000006a4', 'c1000000-0000-4000-8000-000000000012', c_luc, 'pronto', 'rodada', 'ligado',
            (select esperado from _x1 where n = 13), c_agora, c_agora + interval '1 day', 'aprovada', c_agora, 'enviada', c_agora,
            'agenda-cliente:pronto:' || c_luc || ':2026-10-30');
    v := md5((select string_agg(to_jsonb(x)::text, ',' order by x.service_order_id) from public.os_planejamento x));
    v_res := pg_temp.ok(v_res, 'X6d a mensagem sem data (o pronto) e a que não existe não gravam nada',
      public._agenda_cliente_prometer('d5000000-0000-4000-8000-0000000006a4', c_agora) = '{"gravou": false, "motivo": "sem_data"}'::jsonb
      and public._agenda_cliente_prometer('d5000000-0000-4000-8000-0000000006ff', c_agora) = '{"gravou": false, "motivo": "sem_mensagem"}'::jsonb
      and v = md5((select string_agg(to_jsonb(x)::text, ',' order by x.service_order_id) from public.os_planejamento x)));
    -- (f) a OS sem linha de planejamento (Robson): nasce só com o prometido
    j := public._agenda_cliente_gravar_prometido(c_rob, 'firme', date '2026-11-10', date '2026-11-10', 'dono', null, c_agora,
                                                 'falei pro Robson que é dia 10');
    select * into p from public.os_planejamento where service_order_id = c_rob;
    v_res := pg_temp.ok(v_res, 'X6e a OS sem linha de planejamento: a linha nasce só com o prometido (sem dias, sem estimativa)',
      p.service_order_id = c_rob and p.prometido_ate = date '2026-11-10' and p.prometido_fonte = 'dono' and p.dias is null
      and p.estimativa_fonte is null and p.dono_presenca is null and jsonb_array_length(p.historico) = 1
      and p.historico -> 0 ->> 'trecho' = 'falei pro Robson que é dia 10', to_jsonb(p)::text);
    -- (g) o histórico corta nos 20 mais novos
    for i in 1 .. 25 loop
      perform public._agenda_cliente_gravar_prometido(c_rob, 'firme', date '2026-11-10' + i, date '2026-11-10' + i, 'dono', null,
                                                      c_agora + make_interval(mins => i), format('promessa %s', i));
    end loop;
    select * into p from public.os_planejamento where service_order_id = c_rob;
    v_res := pg_temp.ok(v_res, 'X6f o histórico fica em 20 (as mais novas): a última é a 25ª; o original é o da 1ª (ter 10/11)',
      jsonb_array_length(p.historico) = 20 and p.historico -> -1 ->> 'trecho' = 'promessa 25'
      and p.historico -> 0 ->> 'trecho' = 'promessa 6' and p.prometido_original_ate = date '2026-11-10'
      and p.prometido_ate = date '2026-12-05', jsonb_array_length(p.historico)::text);
    -- (h) o tipo inválido e a data que falta: 22023
    begin
      perform public._agenda_cliente_gravar_prometido(c_rob, 'talvez', date '2026-11-10', null, 'dono', null, c_agora, null);
      v := 'aceitou';
    exception when others then v := sqlstate || ': ' || sqlerrm;
    end;
    begin
      perform public._agenda_cliente_gravar_prometido(c_rob, 'firme', null, null, 'dono', null, c_agora, null);
      v := v || ' | aceitou';
    exception when others then v := v || ' | ' || sqlstate;
    end;
    v_res := pg_temp.ok(v_res, 'X6g o tipo que não existe e a promessa sem dia: 22023',
      v = '22023: O que foi dito ao cliente precisa do tipo e do dia. | 22023', v);
    -- (i) o botão antigo: o dia confirmado até o fim agendado (o espelho do Vanderlei: ter 03 a qui 05/11)
    j := public._agenda_cliente_prometer_confirmacao(c_ven, (select scheduled_start_at from public.service_orders where id = c_ven), c_agora);
    select * into p from public.os_planejamento where service_order_id = c_ven;
    v_res := pg_temp.ok(v_res, 'X6h o botão antigo: firme de ter 03/11 ao fim agendado (qui 05/11), fonte confirmacao, sem mensagem',
      (j ->> 'gravou')::boolean and p.prometido_tipo = 'firme' and p.prometido_de = date '2026-11-03'
      and p.prometido_ate = date '2026-11-05' and p.prometido_original_ate = date '2026-11-05'
      and p.prometido_fonte = 'confirmacao' and p.prometido_mensagem_id is null, to_jsonb(p)::text);
    v_res := pg_temp.ok(v_res, 'X6i o botão antigo sem dia, ou de uma OS que não existe, não grava',
      public._agenda_cliente_prometer_confirmacao(c_ven, null, c_agora) = '{"gravou": false, "motivo": "sem_data"}'::jsonb
      and public._agenda_cliente_prometer_confirmacao('d5000000-0000-4000-8000-0000000000ff', c_agora, c_agora)
          = '{"gravou": false, "motivo": "sem_os"}'::jsonb);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$x$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
