-- Fixture da Fase 7g da Agenda de Produção ("mostrar como pensou e provar o trabalho"), SINTÉTICA, por cima da da 7d (fixture-fase7d.sql, que carrega a 7c, a 7b,
-- a 7a e o replay real de 29/10) (spec-fase7g §8.2, com o R9.5-22: a base é a da 7d, como na 7e e na 7f; esta não carrega a da 7f nem a da 7e, e o que a 7g
-- precisar delas entra aqui, por pacote). Roda dentro do begin/rollback do teste (o rodar.mjs passa este arquivo em agenda_teste.fase7g); o que ainda não foi
-- carregado nesta transação é carregado antes. Pode rodar de novo na mesma transação (confere se já está lá). NUNCA rodar em produção.
-- Só primeiros nomes; ids pelo md5 de '7g:…'; as OS são OS-G0, OS-G1, … (o 0 é a desta seção).
--
-- Hoje é qui 19/11/2026 (p_hoje), p_agora 16:36 (depois de explicar_hora); a semana medida é 09 a 14/11 e a semana que vem, 23 a 28/11 (§8.2). Ela não mexe em
-- agenda_config: os 4 modos ficam como cada teste os puser. A equipe é a sintética da 7c: com agenda_teste.fase7b_equipe = 'real' esta fixture recusa.
--
-- O QUE ELA NÃO PROVA (R9.12-8): a produção não tem esta forma. Lá há 1 técnico (o Alex), 0 de 53 alocações com critério, toda ação é da vigia (nenhuma do
-- motor), o material tem fonte nula, 4 de 131 OS têm linha em os_planejamento e 0 de 53 meios-dias têm resultado. Cada pacote roda ao menos 1 caso sobre o
-- replay real (estado-*.tgz). A seção abaixo fixa só a FORMA REAL do que os pacotes seguintes leem para explicar (wf7g_p1_acoes, wf7g_p1_estado, 09/11).
--
-- ═══ O QUE CADA PACOTE ACRESCENTA AQUI, em seção própria no fim (o molde de fixture-fase7e.sql; a §8.2 tem os números) ═══
--   P2  as propostas da semana com as suposições de cada OS (Cerbo com 7 dias úteis, local suposto, uma pessoa…) e a substituição do check-in
--   P3  a semana de 23/11 do "como pensei" (Nelson reservado, Vanderlei do dono, Lenine do gestor, Giancarlo, Kalmar, Rodrigo, o compre até vencido) e os trechos
--       da data dita
--   P4  o ORÇ de 3,5 dias com 9 itens e o ORÇ sem material
--   P5  as marcações da semana de 09/11 (6 do gestor, 1 do dono), as 4 formas do histórico (R9.4-2), as classes rv:energia e rv:conforto
--   P6  a cobertura, a aprovação, o plano cumprido, a estimativa, as compras, as perguntas e as mensagens (só contagem) da semana medida
--   Motivo de ficarem para eles: cada bloco só se prova com a função que o lê; o P1 não tem leitor (R9.12-8).
--
-- A SEÇÃO DO P1: uma OS (OS-G0, Lenine, motorhome, sem linha em os_planejamento: o caso comum) marcada pela vigia, na forma real de produção:
--   a ação   criar, origem vigia (em produção toda ação é da vigia, nenhuma do motor), executada; antes = {alocacoes: [], fim: null} e
--            depois = {alocacoes: [{alocacao_id, payee_id, nome, dia, turno, presenca}], fim}: as chaves reais (o porta de produção fica de fora: ninguém o lê)
--   2 meios  ter 24/11 de manhã e de tarde, o Alex, publicadas: duracao_fonte orcamento (as 41 de produção), criterio unico (R9.5-6: com 1 técnico, o comum),
--            motivos com a frase de texto que a produção grava, suposicoes NULA (toda alocação de antes da 7g)
--   o dono   abertura e fechamento do mesmo dia no depois da ação (as 3 ações criar de produção têm abertura e fechamento), quando a bancada sabe quem é o dono

do $f7g$
declare
  c_os    constant uuid := md5('7g:os:g0')::uuid;
  c_cli   constant uuid := md5('7g:cliente:g0')::uuid;
  c_bem   constant uuid := md5('7g:bem:g0')::uuid;
  c_acao  constant uuid := md5('7g:acao:g0')::uuid;
  c_pub   constant timestamptz := timestamptz '2026-11-16 16:30-03';
  c_dia   constant date := date '2026-11-24';
  v_alex  uuid;
  v_dono  uuid;
  v_m     uuid := md5('7g:aloc:g0:manha')::uuid;
  v_t     uuid := md5('7g:aloc:g0:tarde')::uuid;
  v_depois jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase7b_equipe', true), '') = 'real' then
    raise exception 'fixture-fase7g: é por cima da equipe sintética da 7c (Roberto, João, Rafael): agenda_teste.fase7b_equipe = ''real'' não serve';
  end if;
  if not exists (select 1 from public.service_orders where service_order_number = 'OS-J1') then
    if coalesce(current_setting('agenda_teste.fase7d', true), '') = '' then
      raise exception 'fixture-fase7g: falta a fixture da 7d (agenda_teste.fase7d; rode pela bancada)';
    end if;
    execute current_setting('agenda_teste.fase7d');
  end if;

  if exists (select 1 from public.service_orders where id = c_os) then
    return;  -- já carregada nesta transação
  end if;

  select id into strict v_alex from public.payees where name = 'Alex' and active;
  v_dono := public._agenda_dono(null);

  insert into public.clients (id, type, name, phone) values (c_cli, 'individual', 'Lenine', '554790000700');
  insert into public.vessels (id, client_id, name, asset_type) values (c_bem, c_cli, 'Motorhome', 'Motorhome');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at)
  values (c_os, 'OS-G0', c_cli, c_bem, 'open', 'approved', 'repair', timestamptz '2026-11-12 10:00-03', timestamptz '2026-11-13 10:00-03', timestamptz '2026-11-13 10:00-03');
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (md5('7g:servico:g0')::uuid, c_os, null, 'Troca do inversor', 'unit', 1, 764, 764, timestamptz '2026-11-12 10:00-03');

  -- o depois da ação, na ordem e com as chaves de produção (alocacao_id, payee_id, nome, dia, turno, presenca)
  v_depois := jsonb_build_object('fim', c_dia, 'alocacoes',
    jsonb_build_array(jsonb_build_object('alocacao_id', v_m, 'payee_id', v_alex, 'nome', 'Alex', 'dia', c_dia, 'turno', 'manha', 'presenca', 'turno'),
                      jsonb_build_object('alocacao_id', v_t, 'payee_id', v_alex, 'nome', 'Alex', 'dia', c_dia, 'turno', 'tarde', 'presenca', 'turno'))
    || case when v_dono is null then '[]'::jsonb
            else jsonb_build_array(jsonb_build_object('alocacao_id', md5('7g:aloc:g0:abertura')::uuid, 'payee_id', v_dono, 'nome', 'Gustavo', 'dia', c_dia, 'turno', 'manha', 'presenca', 'abertura'),
                                   jsonb_build_object('alocacao_id', md5('7g:aloc:g0:fechamento')::uuid, 'payee_id', v_dono, 'nome', 'Gustavo', 'dia', c_dia, 'turno', 'tarde', 'presenca', 'fechamento')) end);

  insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, alocacoes_canceladas, payee_id, antes, depois, texto, desfazivel_ate)
  values (c_acao, c_pub, date '2026-11-16', true, 'vigia', 'criar', c_os, array[c_os], array[v_m, v_t], '{}', v_alex,
          jsonb_build_object('alocacoes', '[]'::jsonb, 'fim', null), v_depois,
          'Marquei Lenine em ter 24/11 com Alex (1 dia, estimativa minha).', c_pub + interval '24 hours');

  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, acao_id, duracao_fonte, criterio, motivos, criado_em)
  values (v_m, c_os, v_alex, c_dia, 'manha', 'turno', 'execucao', 'publicada', 'motor', c_pub, c_acao, 'orcamento', 'unico',
          '["tem peça a comprar? (o orçamento não tem nenhuma)"]', c_pub),
         (v_t, c_os, v_alex, c_dia, 'tarde', 'turno', 'execucao', 'publicada', 'motor', c_pub, c_acao, 'orcamento', 'unico',
          '["tem peça a comprar? (o orçamento não tem nenhuma)"]', c_pub);
end
$f7g$;
