-- Fixture da Fase 7f da Agenda de Produção ("falar só o que importa"), SINTÉTICO, por cima da da 7d (fixture-fase7d.sql, que carrega a 7c, a 7b, a 7a
-- e o replay real de 29/10) (spec-fase7f §8.2, com o R8.12-8). Roda dentro do begin/rollback do teste (o rodar.mjs passa este arquivo em
-- agenda_teste.fase7f e o da 7d em agenda_teste.fase7d); o que ainda não foi carregado nesta transação é carregado antes. Pode rodar de novo na mesma
-- transação (confere se já está lá). NUNCA rodar em produção. Só primeiros nomes; ids novos com o prefixo f7f00000 e as OS OS-F1 a OS-F6.
--
-- Dois relógios, e a fixture não usa now(): ter 10/11/2026 17:30 (o bloco) e qui 12/11/2026 16:50 (a quinta). Ela não mexe em agenda_config: os 6 modos
-- ficam como cada teste os puser. A equipe é a sintética da 7c: com agenda_teste.fase7b_equipe = 'real' esta fixture recusa.
--
-- O QUE ELA NÃO PROVA (R8.12-8): a produção não tem esta forma. Lá o Alex é prestador, sem telefone, todo dia; há 0 críticas na história; 0 alocações com
-- resultado; só 1 OS com dia marcado. Cada pacote roda ao menos 1 caso sobre o replay real (estado-*.tgz). O tamanho dos textos, sim, é o real: as perguntas têm
-- de 253 a 449 letras, como as de 05 e 06/11 (R8.4).
--
-- As abertas de antes (do replay e das fixtures de 7a a 7d) são resolvidas aqui: as ÚNICAS perguntas abertas depois de carregar são as 8 da etapa. Quem quiser
-- as outras não carrega esta fixture.
--
-- As OS (uma linha de serviço cada; só Nelson e Flávio têm linha em os_planejamento, porque OS sem linha é o caso comum: 4 de 131, R8.12-3):
--   OS-F1 Nelson     veleiro; por estimativa, 3 dias: ter 17/11 com o Alex, qua 18 e qui 19/11 com o Roberto; o Cerbo da Kamell, compre até qui 12/11;
--                    prometido em faixa, 16 a 21/11, pela mensagem semana enviada
--   OS-F2 Lenine     motorhome; marcado hoje pelo gestor (seg 16/11 com o Alex), sem peça; sex 13/11 com o Roberto criada qua 11/11 10:00 (o convite, a
--                    menos de 72 h) e qui 12/11 de manhã com o Roberto (o convite antigo, sem resposta, prazo vencido)
--   OS-F3 Vanderlei  motorhome; hoje, 4 meios-dias: Alex e Rafael, manhã e tarde. A tarde do Alex não foi cumprida por material, e passou para qua 11/11 de manhã
--   OS-F4 Flávio     lancha; o cliente confirmou qua 11/11 (client_confirmed_for) e o prometido é firme nesse dia; crítica nao_cabe; Roberto na qua 11/11
--   OS-F5 Giancarlo  lancha; nao_cabe sem prometido, recomendação 1; sem plano e sem linha
--   OS-F6 Tadeu      motorhome; por estimativa (seg 23/11 com o Alex) sem material completo: compra pendente
--
-- As perguntas, todas em modo ligado:
--   padrao_do_dono                       sem OS, a mais velha
--   duracao (Nelson), material_conferir (Lenine)
--                                        mostradas no fechamento de seg 09/11 com o prazo escrito: vencem ter 10/11 18:00
--   fornecedores_prazo (Correa)          sem OS, nunca mostrada
--   parada (Vanderlei)                   mostrada sem prazo: carona de seg 09/11; não liga o relógio
--   nao_cabe (Flávio)                    crítica, prometido firme: espera o cliente
--   nao_cabe (Giancarlo)                 crítica, recomendação 1, sem veto_espera: tem o que a regra da spec pedia, e nunca vence sozinha (P2)
--   diaria (Roberto)                     crítica, dinheiro: nunca vence
-- São 8 abertas, não contando conferencia: a spec conta 7 + a diária. O teto de 5 deixa 3 acima enquanto a diária estiver aberta.
--
-- As ações (ter 10/11): encaixe do Lenine (criar, vigia, não contada); mover Vanderlei (mover, vigia, não contada); cancelar a tarde do Roberto no Flávio de ter
-- 10/11, dia em que ele já tinha ficha (a exceção); e uma em sombra (executada false, "Em teste: …").
--
-- A equipe: previsto do Roberto enviado qui 05/11 (ter 17 e qua 18); o plano de agora tem qua 18 e qui 19 (a mudança); a ficha ligada dele de ter 10/11; o convite
-- antigo de qui 12/11, sem resposta. O João segue sem telefone (AG7-13).
--
-- O cliente: Nelson com a mensagem semana enviada seg 09/11 (faixa 16 a 21/11). Os remanejos da §8.2 (dentro e fora da faixa) não entram aqui: quem os faz é o teste
-- do P6, com a função de verdade.

do $f7f$
declare
  c_cli     constant text := 'f7f00000-0000-4000-8000-0000000001';   -- + 2 dígitos: os clientes
  c_bem     constant text := 'f7f00000-0000-4000-8000-0000000002';   -- + 2 dígitos: os bens
  c_os      constant text := 'f7f00000-0000-4000-8000-000000097';    -- + 3 dígitos: as OS (301 a 306 = F1 a F6)
  c_perg    constant text := 'f7f00000-0000-4000-8000-0000000005';   -- + 2 dígitos: as perguntas
  c_acao    constant text := 'f7f00000-0000-4000-8000-0000000006';   -- + 2 dígitos: as ações
  c_pubs    constant timestamptz := timestamptz '2026-11-05 16:30-03';  -- a publicação de qui 05/11
  c_ontem   constant timestamptz := timestamptz '2026-11-09 17:30-03';  -- o fechamento de seg 09/11
  c_prazo   constant timestamptz := timestamptz '2026-11-10 18:00-03';  -- o prazo escrito naquele fechamento
  c_agora   constant timestamptz := timestamptz '2026-11-10 14:00-03';  -- quando a vigia mexeu, hoje
  c_opcoes  constant jsonb := '[{"n": 1, "texto": "Passa para a semana seguinte, sem mudar o que já está marcado"}, {"n": 2, "texto": "Mantém o dia e chama mais alguém"}]';
  v_dono_u  uuid;
  v_alex    uuid;
  v_roberto uuid;
  v_rafael  uuid;
  v_os      uuid;
  v_id      uuid;
  v_le1     uuid;
  v_le2     uuid;
  v_vt      uuid;
  v_vn      uuid;
  v_fl      uuid;
  v_hoje_antes text;
  r         record;
begin
  -- ── 0. A base: a 7d (que carrega a 7c, a 7b, a 7a e o replay) ──────────────────────────────────────
  if coalesce(current_setting('agenda_teste.fase7b_equipe', true), '') = 'real' then
    raise exception 'fixture-fase7f: é por cima da equipe sintética da 7c (Roberto, João, Rafael): agenda_teste.fase7b_equipe = ''real'' não serve';
  end if;
  if not exists (select 1 from public.service_orders where service_order_number = 'OS-J1') then
    if coalesce(current_setting('agenda_teste.fase7d', true), '') = '' then
      raise exception 'fixture-fase7f: falta a fixture da 7d (agenda_teste.fase7d; rode pela bancada)';
    end if;
    execute current_setting('agenda_teste.fase7d');
  end if;

  if exists (select 1 from public.service_orders where service_order_number = 'OS-F1') then
    return;  -- já carregada nesta transação
  end if;

  select id into strict v_dono_u from public.app_users where role = 'admin' and active order by id limit 1;
  select id into strict v_alex from public.payees where name = 'Alex' and active;
  select id into strict v_roberto from public.payees where name = 'Roberto' and active;
  select id into strict v_rafael from public.payees where name = 'Rafael' and active;

  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'fixture 7f: fora do cenário' where estado = 'aberta';

  -- ── 1. As OS ────────────────────────────────────────────────────────────────────────────────────────
  for r in
    select * from (values
      -- n,   número,  c,    nome,        bem,         serviço,                            meios
      ('301', 'OS-F1', '01', 'Nelson',    'Veleiro',   'Revisão do banco de baterias',     6),
      ('302', 'OS-F2', '02', 'Lenine',    'Motorhome', 'Troca do inversor',                6),
      ('303', 'OS-F3', '03', 'Vanderlei', 'Motorhome', 'Instalação de carregador',         4),
      ('304', 'OS-F4', '04', 'Flávio',    'Lancha',    'Revisão do piloto automático',     2),
      ('305', 'OS-F5', '05', 'Giancarlo', 'Lancha',    'Troca do GPS',                     2),
      ('306', 'OS-F6', '06', 'Tadeu',     'Motorhome', 'Instalação de placa solar',        2)
    ) as t(n, numero, c, nome, bem, servico, meios)
  loop
    v_os := (c_os || r.n)::uuid;
    insert into public.clients (id, type, name, phone) values ((c_cli || r.c)::uuid, 'individual', r.nome, '55479000003' || r.c);
    insert into public.vessels (id, client_id, name, asset_type) values ((c_bem || r.c)::uuid, (c_cli || r.c)::uuid, r.bem, r.bem);
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                       created_at, updated_at, converted_to_os_at)
    values (v_os, r.numero, (c_cli || r.c)::uuid, (c_bem || r.c)::uuid, 'open', 'approved', 'repair',
            timestamptz '2026-10-28 10:00-03', timestamptz '2026-10-30 10:00-03', timestamptz '2026-10-30 10:00-03');
    insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                               unit_price_snapshot, line_total, created_at)
    values (md5('f7f:servico:' || r.n)::uuid, v_os, null, r.servico, 'unit', 1, 382 * r.meios, 382 * r.meios, timestamptz '2026-10-28 10:00-03');
  end loop;

  -- Só 2 das 6 têm linha em os_planejamento: Nelson (a faixa) e Flávio (firme, confirmado)
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, prometido_tipo, prometido_de, prometido_ate,
                                      prometido_original_ate, prometido_em, prometido_fonte, atualizado_por)
  values ((c_os || '301')::uuid, 3, 'orcamento', timestamptz '2026-10-30 10:00-03', 'faixa', date '2026-11-16', date '2026-11-21',
          date '2026-11-21', timestamptz '2026-11-09 10:00-03', 'mensagem', v_dono_u),
         ((c_os || '304')::uuid, 1, 'dono', timestamptz '2026-10-30 10:00-03', 'firme', date '2026-11-11', date '2026-11-11',
          date '2026-11-11', timestamptz '2026-11-06 10:00-03', 'dono', v_dono_u);
  update public.service_orders set client_confirmed_for = timestamptz '2026-11-11 08:00-03' where id = (c_os || '304')::uuid;

  -- ── 2. O material ───────────────────────────────────────────────────────────────────────────────────
  insert into public.os_material (id, service_order_id, origem, service_order_service_id, descricao, quantidade_necessaria, quantidade_na_mao, critico,
                                  situacao, fornecedor_nome, compre_ate, compre_ate_base, compre_ate_em, atualizado_por)
  values (md5('f7f:material:301')::uuid, (c_os || '301')::uuid, 'texto_livre', md5('f7f:servico:301')::uuid, 'Cerbo GX', 1, 0, true, 'falta', 'Kamell',
          date '2026-11-12', '{"primeiro": "2026-11-17", "folga": 1, "prazo": 3, "prazo_fonte": "padrao", "interno": 1}', timestamptz '2026-11-09 10:00-03', v_dono_u),
         (md5('f7f:material:306')::uuid, (c_os || '306')::uuid, 'texto_livre', md5('f7f:servico:306')::uuid, 'Placa solar 550 W', 2, 0, true, 'falta', 'Correa',
          date '2026-11-16', '{"primeiro": "2026-11-23", "folga": 1, "prazo": 4, "prazo_fonte": "padrao", "interno": 1}', timestamptz '2026-11-09 10:00-03', v_dono_u);

  -- ── 3. O plano ──────────────────────────────────────────────────────────────────────────────────────
  -- o resultado é do dia que já chegou: o "hoje" da agenda é ter 10/11 enquanto o plano entra
  v_hoje_antes := current_setting('agenda.hoje', true);
  perform set_config('agenda.hoje', '2026-11-10', true);
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte,
                                       resultado, motivo, resultado_via, resultado_em, criado_em)
  select md5('f7f:aloc:' || t.n || ':' || t.quem || ':' || t.dia || ':' || t.turno)::uuid, (c_os || t.n)::uuid, t.payee, t.dia::date, t.turno, 'turno', 'execucao',
         'publicada', 'motor', c_pubs, t.fonte, t.resultado, t.motivo,
         case when t.resultado is not null then 'dia_feito' end,
         case when t.resultado is not null then c_agora end, t.criado
    from (values
      ('301', 'alex',    v_alex,    '2026-11-17', 'manha', 'orcamento', null,           null,       c_pubs),
      ('301', 'alex',    v_alex,    '2026-11-17', 'tarde', 'orcamento', null,           null,       c_pubs),
      ('301', 'roberto', v_roberto, '2026-11-18', 'manha', 'orcamento', null,           null,       c_pubs),
      ('301', 'roberto', v_roberto, '2026-11-18', 'tarde', 'orcamento', null,           null,       c_pubs),
      ('301', 'roberto', v_roberto, '2026-11-19', 'manha', 'orcamento', null,           null,       c_pubs),
      ('301', 'roberto', v_roberto, '2026-11-19', 'tarde', 'orcamento', null,           null,       c_pubs),
      ('302', 'alex',    v_alex,    '2026-11-16', 'manha', 'orcamento', null,           null,       timestamptz '2026-11-10 14:00-03'),
      ('302', 'alex',    v_alex,    '2026-11-16', 'tarde', 'orcamento', null,           null,       timestamptz '2026-11-10 14:00-03'),
      ('302', 'roberto', v_roberto, '2026-11-13', 'manha', 'orcamento', null,           null,       timestamptz '2026-11-11 10:00-03'),
      ('302', 'roberto', v_roberto, '2026-11-13', 'tarde', 'orcamento', null,           null,       timestamptz '2026-11-11 10:00-03'),
      ('302', 'roberto', v_roberto, '2026-11-12', 'manha', 'orcamento', null,           null,       timestamptz '2026-11-09 10:00-03'),
      ('303', 'alex',    v_alex,    '2026-11-10', 'manha', 'dono',      'cumprido',     null,       c_pubs),
      ('303', 'alex',    v_alex,    '2026-11-10', 'tarde', 'dono',      'nao_cumprido', 'material', c_pubs),
      ('303', 'rafael',  v_rafael,  '2026-11-10', 'manha', 'dono',      'cumprido',     null,       c_pubs),
      ('303', 'rafael',  v_rafael,  '2026-11-10', 'tarde', 'dono',      'cumprido',     null,       c_pubs),
      ('303', 'alex',    v_alex,    '2026-11-11', 'manha', 'dono',      null,           null,       c_agora),
      ('304', 'roberto', v_roberto, '2026-11-11', 'manha', 'dono',      null,           null,       c_pubs),
      ('304', 'roberto', v_roberto, '2026-11-11', 'tarde', 'dono',      null,           null,       c_pubs),
      ('306', 'alex',    v_alex,    '2026-11-23', 'manha', 'orcamento', null,           null,       c_pubs),
      ('306', 'alex',    v_alex,    '2026-11-23', 'tarde', 'orcamento', null,           null,       c_pubs)
    ) as t(n, quem, payee, dia, turno, fonte, resultado, motivo, criado);

  -- a tarde do Roberto no Flávio de hoje, que a exceção cancelou: ele já tinha a ficha de hoje
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte,
                                       cancelada_em, cancelada_motivo, criado_em)
  values (md5('f7f:aloc:304:roberto:2026-11-10:tarde')::uuid, (c_os || '304')::uuid, v_roberto, date '2026-11-10', 'tarde', 'turno', 'execucao',
          'cancelada', 'motor', c_pubs, 'dono', c_agora, 'cliente', c_pubs);
  perform set_config('agenda.hoje', coalesce(v_hoje_antes, ''), true);
  v_fl := md5('f7f:aloc:304:roberto:2026-11-10:tarde')::uuid;
  v_le1 := md5('f7f:aloc:302:alex:2026-11-16:manha')::uuid;
  v_le2 := md5('f7f:aloc:302:alex:2026-11-16:tarde')::uuid;
  v_vt := md5('f7f:aloc:303:alex:2026-11-10:tarde')::uuid;
  v_vn := md5('f7f:aloc:303:alex:2026-11-11:manha')::uuid;

  -- ── 4. As perguntas ─────────────────────────────────────────────────────────────────────────────────
  insert into public.agenda_perguntas (id, tipo, chave, service_order_id, os_ids, payee_id, dia, perda_em, texto, opcoes, recomendacao, modo, criada_em, expira_em,
                                       veto_ate, mostrada_vezes, mostrada_em, mostrada_via, carona_em)
  select (c_perg || t.c)::uuid, t.tipo, t.chave, t.os, case when t.os is null then '{}'::uuid[] else array[t.os] end, t.payee, null::date, t.perda, t.texto,
         t.opcoes, t.rec, 'ligado', t.criada, null::timestamptz, t.veto, t.vezes, t.vista, t.via, t.carona
    from (values
      ('01', 'padrao_do_dono', 'padrao_do_dono:2026-11-09', null::uuid, null::uuid, null::date,
       'Quais dias você fica em campo na semana de 16/11? Hoje eu conto você só para abrir e fechar, e com isso o gestor marca os serviços que dependem de você para a semana seguinte, sem saber se você de fato estaria lá. Me diga os dias que você fica, nem que seja só aproximado.',
       '[]'::jsonb, null::smallint, timestamptz '2026-11-03 09:00-03', null::timestamptz, 0, null::timestamptz, null::text, null::timestamptz),
      ('02', 'duracao', 'duracao:' || (c_os || '301'), (c_os || '301')::uuid, null, date '2026-11-12',
       'A OS do Nelson (veleiro, Revisão do banco de baterias) ainda não tem a duração dita. Pelo orçamento, contei 3 dias de trabalho, e é com esse número que ela está no plano de ter 17 a qui 19/11. Se você souber que é mais ou menos do que isso, me diga agora, para eu não marcar o resto da semana em cima de um número errado.',
       '[]'::jsonb, null, timestamptz '2026-11-04 09:00-03', c_prazo, 1, c_ontem, 'fechamento', null),
      ('03', 'material_conferir', 'material_conferir:' || (c_os || '302'), (c_os || '302')::uuid, null, date '2026-11-13',
       'A OS do Lenine (motorhome, Troca do inversor) entrou no plano sem nenhuma peça conferida. O orçamento não lista material nenhum, e eu não sei se isso quer dizer que tudo está na mão ou que ninguém olhou. Tem peça a comprar para este serviço? Se tiver, me diga qual, para eu cobrar a compra no prazo certo e não marcar o dia à toa.',
       '[]'::jsonb, null, timestamptz '2026-11-05 09:00-03', c_prazo, 1, c_ontem, 'fechamento', null),
      ('04', 'fornecedores_prazo', 'fornecedores_prazo:correa', null, null, null,
       'A Correa não tem prazo de entrega cadastrado, e há compra dela na carteira. Sem esse número eu conto o prazo padrão, que pode estar longe do real, e o "compre até" sai errado para tudo o que vem dela. Quantos dias úteis ela costuma levar para entregar aqui? Uma resposta aproximada já serve, e eu corrijo depois pela primeira entrega real.',
       '[]'::jsonb, null, timestamptz '2026-11-06 09:00-03', null, 0, null, null, null),
      ('05', 'parada', 'parada:' || (c_os || '303'), (c_os || '303')::uuid, null, date '2026-11-12',
       'A OS do Vanderlei (motorhome, Instalação de carregador) está parada há 4 dias úteis, com o plano esperando o material que faltou. Eu não sei se o serviço continua de pé do jeito que está ou se mudou alguma coisa do lado do cliente. Quer que eu deixe como está no plano, ou tem algo que eu deva saber antes de mexer nele?',
       '[]'::jsonb, null, timestamptz '2026-11-07 09:00-03', null, 1, c_ontem, 'conversa', c_ontem),
      ('06', 'nao_cabe', 'nao_cabe:' || (c_os || '304'), (c_os || '304')::uuid, null, date '2026-11-11',
       'O serviço do Flávio (lancha, Revisão do piloto automático) não cabe mais em qua 11/11 com o que foi cancelado hoje, e o cliente já confirmou esse dia. Para manter, preciso de mais uma pessoa; para mudar, ele precisa ser avisado. O que eu faço? 1) Passa para a semana seguinte, sem mudar o que já está marcado. 2) Mantém o dia e chama mais alguém.',
       c_opcoes, 1::smallint, timestamptz '2026-11-08 09:00-03', null, 0, null, null, null),
      ('07', 'nao_cabe', 'nao_cabe:' || (c_os || '305'), (c_os || '305')::uuid, null, date '2026-11-12',
       'O serviço do Giancarlo (lancha, Troca do GPS) não cabe nas 2 próximas semanas com a equipe que eu tenho, e nada foi dito ao cliente ainda. Para entrar, ou ele fica para depois do que já está marcado, ou alguém precisa vir a mais. O que eu faço? 1) Passa para a semana seguinte, sem mudar o que já está marcado. 2) Mantém o dia e chama mais alguém.',
       c_opcoes, 1::smallint, timestamptz '2026-11-09 09:00-03', null, 0, null, null, null),
      ('08', 'diaria', 'diaria:roberto:2026-11-09', (c_os || '303')::uuid, v_roberto, date '2026-11-12',
       'A diária do Roberto de seg 09/11 ficou sem a OS ligada, e ela entra no custo do Vanderlei se for dele. Sem essa resposta o acerto da semana fica pendente, e eu não fecho o custo do serviço. Essa diária é do Vanderlei? 1) É do Vanderlei, liga ela nessa OS. 2) Não é do Vanderlei: me diga de quem é, para eu ligar na OS certa.',
       '[{"n": 1, "texto": "É do Vanderlei"}, {"n": 2, "texto": "Não é do Vanderlei"}]'::jsonb, 1::smallint, timestamptz '2026-11-09 18:00-03', null, 0, null, null, null)
    ) as t(c, tipo, chave, os, payee, perda, texto, opcoes, rec, criada, veto, vezes, vista, via, carona);

  -- ── 5. As ações de hoje ─────────────────────────────────────────────────────────────────────────────
  insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, alocacoes_canceladas, payee_id, texto, desfazivel_ate)
  values ((c_acao || '01')::uuid, c_agora, date '2026-11-10', true, 'vigia', 'criar', (c_os || '302')::uuid, array[(c_os || '302')::uuid], array[v_le1, v_le2], '{}', v_alex,
          'Marquei Lenine em seg 16/11 com Alex (3 dias, estimativa minha).', c_agora + interval '24 hours'),
         ((c_acao || '02')::uuid, c_agora, date '2026-11-10', true, 'vigia', 'mover', (c_os || '303')::uuid, array[(c_os || '303')::uuid], array[v_vn], array[v_vt], v_alex,
          'Passei Vanderlei da tarde de hoje para qua 11/11 de manhã.', c_agora + interval '24 hours'),
         ((c_acao || '03')::uuid, c_agora, date '2026-11-10', true, 'vigia', 'cancelar', (c_os || '304')::uuid, array[(c_os || '304')::uuid], '{}', array[v_fl], v_roberto,
          'Tirei o Roberto da tarde de hoje no Flávio: o cliente pediu.', c_agora + interval '24 hours'),
         ((c_acao || '04')::uuid, c_agora, date '2026-11-10', false, 'vigia', 'mover', (c_os || '305')::uuid, array[(c_os || '305')::uuid], '{}', '{}', null,
          'Em teste: eu passaria Giancarlo para a semana de 23/11.', null);

  -- ── 6. A equipe ─────────────────────────────────────────────────────────────────────────────────────
  insert into public.agenda_equipe_mensagens (id, payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, dias, alocacao_ids)
  values (md5('f7f:previsto:roberto')::uuid, v_roberto, date '2026-11-05', 'previsto', 'ligado',
          'Roberto, semana que vem (previsto, pode mudar): ter 17 e qua 18/11. Se algum desses dias não der, me fala.', timestamptz '2026-11-05 19:30-03',
          'enfileirada', 'agenda-equipe:previsto:roberto:2026-11-05', array[date '2026-11-17', date '2026-11-18'], null),
         (md5('f7f:ficha:roberto')::uuid, v_roberto, date '2026-11-10', 'ficha', 'ligado',
          'Roberto, amanhã (ter 10/11): 8h na lancha do Flávio.', timestamptz '2026-11-09 19:30-03', 'enfileirada', 'agenda-equipe:ficha:roberto:2026-11-10', null, null),
         (md5('f7f:convite:roberto')::uuid, v_roberto, date '2026-11-12', 'convite', 'ligado',
          'Roberto, apareceu serviço para qui 12/11: 8h no motorhome do Lenine. Pode vir? Responde SIM ou NÃO até qua 11/11 às 19:30.', timestamptz '2026-11-09 10:30-03',
          'enfileirada', 'agenda-equipe:convite:roberto:2026-11-12', array[date '2026-11-12'], array[md5('f7f:aloc:302:roberto:2026-11-12:manha')::uuid]);

  -- ── 7. O cliente ────────────────────────────────────────────────────────────────────────────────────
  v_id := md5('f7f:semana:301')::uuid;
  insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de, faixa_ate, prometido_tipo, modo, texto, base,
                                               enviar_em, valida_ate, aprovacao, estado, dedupe_key, enviada_em, criada_em)
  values (v_id, (c_cli || '01')::uuid, (c_os || '301')::uuid, 'semana', 'compra_feita', 'rodada', date '2026-11-16', date '2026-11-16', date '2026-11-21', 'faixa', 'ligado',
          'Olá, Nelson! Aqui é o Gustavo, da HBR. O serviço no seu veleiro está previsto para a semana de 16/11 (segunda 16/11 a sexta 20/11), com uns 3 dias de trabalho. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.',
          '{}', timestamptz '2026-11-09 10:00-03', timestamptz '2026-11-09 19:00-03', 'livre', 'enviada', 'agenda-cliente:semana:' || (c_os || '301') || ':2026-11-16',
          timestamptz '2026-11-09 10:00-03', timestamptz '2026-11-09 09:00-03');
end
$f7f$;
