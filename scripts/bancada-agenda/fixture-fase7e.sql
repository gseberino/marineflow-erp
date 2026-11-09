-- Fixture da Fase 7e da Agenda de Produção ("a margem que aprende"), SINTÉTICA, por cima da da 7d (fixture-fase7d.sql, que carrega a 7c, a 7b, a 7a e o replay real de 29/10) (spec-fase7e
-- §8.2, com o R7.12-8). Não carrega a da 7f: a história de novembro e dezembro da §8.2 fica limpa para o que a folga mede. Roda dentro do begin/rollback do teste (o rodar.mjs passa este
-- arquivo em agenda_teste.fase7e); o que ainda não foi carregado nesta transação é carregado antes. Pode rodar de novo na mesma transação (confere se já está lá). NUNCA rodar em produção.
-- Só primeiros nomes; ids novos com o prefixo e7e00000; as OS são OS-E0, OS-E1, … (o 0 é a desta seção).
--
-- Hoje é qui 07/01/2027 (p_hoje), p_agora 16:05; a história vai de 02/11/2026 a 06/01/2027 (§8.2). Ela não mexe em agenda_config: os 6 modos ficam como cada teste os puser. A equipe é a
-- sintética da 7c: com agenda_teste.fase7b_equipe = 'real' esta fixture recusa.
--
-- O QUE ELA NÃO PROVA (R7.12-8): a produção não tem esta forma. Lá o Alex é prestador, sem telefone nem perfil de diária; há 0 conferidas de verdade; 4 de 131 OS têm linha em os_planejamento. Cada pacote
-- roda ao menos 1 caso sobre o replay real (estado-*.tgz). A seção abaixo fixa só a FORMA REAL das linhas de material, que a §8.2 dá por errado (R7.5-3, 4, 5, 6).
--
-- ═══ O QUE CADA PACOTE ACRESCENTA AQUI, em seção própria no fim (o molde de fixture-fase6.sql; a §8.2 tem os números) ═══
--   P2  as 8 OS do viés (E1 a E4, G1 a G3, B1), as 2 do dono, as 5 inválidas, com as alocações, os resultados, as diárias ligadas e os dias do início; as linhas de compra e os retratos
--   P3  a marcação com o viés de 1,00 em uso; os dias do dono com a correção (R7.3-2)
--   P4  as 8 semanas da folga e a semana de 28/12 sem compromisso
--   P4b a urgência e o puxar (a véspera de 06/01, 17:31)
--   P5  nada: as OS do P2 dão razão de prazo 1,00 em todas, e o teste do P5 põe as 8 razões da §8.2 direto nas medidas (a medida de verdade tem o caso P1w dele)
--   P6  as compras: tempo interno, folga, fornecedor (R7.3-5: o padrão de compra_interna_du é 1, e a peça sem fornecedor conta 7)
--   Motivo de ficarem para eles: cada bloco só se prova com a função que o lê; o P1 não tem leitor (R7.12-8: fixture que confirma a spec, e não a produção, é a classe 8 de defeito).
--
-- A SEÇÃO DO P1: uma OS (OS-E0) com as 3 linhas de material na forma real de produção:
--   m1  "Inversor"   crítico, fonte NULA (19 das 20 linhas de produção; R7.5-4), comprada pelo dono: historico na forma real, {em, de, para, por, autor, trecho, nota}, SEM a chave depois (R7.5-3)
--   m2  "Parafusos"  crítico = true, como todas as de produção (R7.5-5): o miúdo só existe calculado (_agenda_material_critico, P2), nunca nesta coluna; fonte nula
--   m3  "Cerbo GX"   com o "compre até" gravado pelo P10: compre_ate_base na forma real, {primeiro, folga, prazo, corridos, prazo_fonte, interno} (R7.5-6)

do $f7e$
declare
  c_os  constant uuid := 'e7e00000-0000-4000-8000-000000000e00';
  c_cli constant uuid := 'e7e00000-0000-4000-8000-000000000c00';
  c_bem constant uuid := 'e7e00000-0000-4000-8000-000000000b00';
  v_autor uuid;
begin
  if coalesce(current_setting('agenda_teste.fase7b_equipe', true), '') = 'real' then
    raise exception 'fixture-fase7e: é por cima da equipe sintética da 7c (Roberto, João, Rafael): agenda_teste.fase7b_equipe = ''real'' não serve';
  end if;
  if not exists (select 1 from public.service_orders where service_order_number = 'OS-J1') then
    if coalesce(current_setting('agenda_teste.fase7d', true), '') = '' then
      raise exception 'fixture-fase7e: falta a fixture da 7d (agenda_teste.fase7d; rode pela bancada)';
    end if;
    execute current_setting('agenda_teste.fase7d');
  end if;

  if exists (select 1 from public.service_orders where id = c_os) then
    return;  -- já carregada nesta transação
  end if;

  select id into strict v_autor from public.app_users where role = 'admin' and active order by id limit 1;

  insert into public.clients (id, type, name, phone) values (c_cli, 'individual', 'Lia', '554790000e00');
  insert into public.vessels (id, client_id, name, asset_type) values (c_bem, c_cli, 'Motorhome', 'Motorhome');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at)
  values (c_os, 'OS-E0', c_cli, c_bem, 'open', 'approved', 'repair', timestamptz '2026-11-30 10:00-03', timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-01 10:00-03');
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (md5('e7e:servico:e0')::uuid, c_os, null, 'Troca do inversor', 'unit', 1, 1528, 1528, timestamptz '2026-11-30 10:00-03');

  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, comprado_em, historico, atualizado_por)
  values (md5('e7e:material:m1')::uuid, c_os, 'dono', 'Inversor', 1, 0, true, 'comprado', null, date '2026-12-04',
          jsonb_build_array(jsonb_build_object('em', timestamptz '2026-12-04 10:00-03', 'de', 'falta', 'para', 'comprado', 'por', 'dono', 'autor', v_autor, 'trecho', 'comprei o inversor da Lia', 'nota', null)),
          v_autor);
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_por)
  values (md5('e7e:material:m2')::uuid, c_os, 'dono', 'Parafusos', 4, 0, true, 'falta', null, v_autor);
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, compre_ate, compre_ate_em, compre_ate_base, atualizado_por)
  values (md5('e7e:material:m3')::uuid, c_os, 'dono', 'Cerbo GX', 1, 0, true, 'falta', null, date '2026-12-10', timestamptz '2026-12-04 10:00-03',
          jsonb_build_object('primeiro', date '2026-12-15', 'folga', 1, 'prazo', 2, 'corridos', false, 'prazo_fonte', 'sem_fornecedor', 'interno', 1), v_autor);
end
$f7e$;

-- ═══ A SEÇÃO DO P2 (a medição): as OS concluídas da §8.2, com as alocações, os resultados e as diárias ═══
-- As datas ficam de 01/06 a set/2026, FORA das 12 semanas que a folga da semana olha (07/01 − 12 semanas): o P4 e a folga não enxergam estas alocações. A equipe daqui é só desta seção:
-- Caio (diarista, com perfil) e Zeca (como o Alex de produção: prestador sem perfil de diária). O dono vem de _agenda_dono.
--   OS       classe         MO        meios-dias                 pm_estimados → pm_reais
--   E1       rv:energia     3.820     11 cumpridos + 1 parcial   10 → 11,5 (1,15)
--   E2       rv:energia     1.910     6                           5 → 6    (1,20)
--   E3       rv:energia     1.910     6 + 1 parcial               5 → 6,5  (1,30)
--   E4       rv:energia     3.820     14 + 1 parcial             10 → 14,5 (1,45)
--   G1       rv:geral       1.528     3                           4 → 3    (0,75)
--   G2       rv:geral       1.910     4                           5 → 4    (0,80)
--   G3       rv:geral       3.820     8 + 1 parcial              10 → 8,5  (0,85)
--   B1       barco:energia  1.910     7                           5 → 7    (1,40)
--   D1, D2   rv:diagnóstico  250      o dono, 5 dias ditos (10 meios de turno): 10,5 e 11 → razao_dono 1,05 e 1,10; sem estimativa pelo valor (R7.5-9)
--   As inválidas de propósito (cada uma pelo motivo_razao dela):
--   I1 sem_diaria (com o diarista no plano, sem a diária ligada), I2 conferencia_incompleta (1 meio-dia sem_registro), I3 sem_estimativa (OS sem base), I5 sem_trabalho (só nao_cumprido); R1 a "reaberta" (o teste a reabre)
--   V1 sem check-in, com dia cumprido, vale (R7.4); Z1 com o Zeca sem perfil, sem diária, vale (R7.4)
-- E as linhas de material (na OS-E0, a de cima): m4 (a nota), m5 (o histórico: forma real) e m6 (balcão inferido). As 3 de cima (m1 a m3) continuam como o P1 as deixou.
do $f7e_p2$
declare
  c_cli  constant uuid := 'e7e00000-0000-4000-8000-000000000c02';
  c_rv   constant uuid := 'e7e00000-0000-4000-8000-000000000b02';
  c_bar  constant uuid := 'e7e00000-0000-4000-8000-000000000b03';
  c_caio constant uuid := 'e7e00000-0000-4000-8000-00000000aa01';
  c_zeca constant uuid := 'e7e00000-0000-4000-8000-00000000aa02';
  c_perf constant uuid := 'e7e00000-0000-4000-8000-00000000ab01';
  c_os0  constant uuid := 'e7e00000-0000-4000-8000-000000000e00';
  v_autor uuid;
  v_dono  uuid := public._agenda_dono(null);
  v_cur   date := date '2026-08-03';
  v_cur_d date := date '2026-06-01';
  r       record;
  v_os    uuid;
  v_ini   date;
  v_fim   date;
  v_dia   date;
  v_n     int;
  i       int;
  v_payee uuid;
  v_res   text;
  v_nota  uuid := md5('e7e:remessa:1')::uuid;
begin
  if exists (select 1 from public.service_orders where service_order_number = 'OS-7E-E1') then
    return;  -- já carregada nesta transação
  end if;
  select id into strict v_autor from public.app_users where role = 'admin' and active order by id limit 1;
  perform set_config('agenda.hoje', '2027-01-07', true);
  perform set_config('agenda.porta', 'on', true);

  insert into public.clients (id, type, name, phone) values (c_cli, 'individual', 'Nina', '554790000e02');
  insert into public.vessels (id, client_id, name, asset_type) values (c_rv, c_cli, 'Motorhome', 'Motorhome'), (c_bar, c_cli, 'Lancha', 'Lancha');
  insert into public.payees (id, name, kind, active) values (c_caio, 'Caio', 'prestador', true), (c_zeca, 'Zeca', 'prestador', true);
  insert into public.work_profiles (id, payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio)
  values (c_perf, c_caio, 'diarista', 'diaria', 200, date '2026-01-01');

  for r in select * from (values
    ('E1', 'rv',    'Instalação de inversor e baterias', 3820::numeric, 11, 1, 'cumprido', true, true,  c_caio),
    ('E2', 'rv',    'Instalação de inversor e baterias', 1910,           6, 0, 'cumprido', true, true,  c_caio),
    ('E3', 'rv',    'Instalação de inversor e baterias', 1910,           6, 1, 'cumprido', true, true,  c_caio),
    ('E4', 'rv',    'Instalação de inversor e baterias', 3820,          14, 1, 'cumprido', true, true,  c_caio),
    ('G1', 'rv',    'Reparo na porta da cabine',         1528,           3, 0, 'cumprido', true, true,  c_caio),
    ('G2', 'rv',    'Reparo na porta da cabine',         1910,           4, 0, 'cumprido', true, true,  c_caio),
    ('G3', 'rv',    'Reparo na porta da cabine',         3820,           8, 1, 'cumprido', true, true,  c_caio),
    ('B1', 'barco', 'Instalação de inversor e baterias', 1910,           7, 0, 'cumprido', true, true,  c_caio),
    ('I1', 'rv',    'Reparo na porta da cabine',          764,           2, 0, 'cumprido', false, true, c_caio),
    ('I2', 'rv',    'Reparo na porta da cabine',          764,           1, 0, 'sem_registro', true, true, c_caio),
    ('I3', 'rv',    'Sem preço',                            0,           2, 0, 'cumprido', true, true,  c_caio),
    ('I5', 'rv',    'Reparo na porta da cabine',          764,           2, 0, 'nao_cumprido', true, true, c_caio),
    ('R1', 'rv',    'Reparo na porta da cabine',          764,           2, 0, 'cumprido', true, true,  c_caio),
    ('V1', 'rv',    'Reparo na porta da cabine',          764,           2, 0, 'cumprido', true, false, c_caio),
    ('Z1', 'rv',    'Reparo na porta da cabine',          764,           2, 0, 'cumprido', false, true, c_zeca),
    ('D1', 'rv',    'DIAGNÓSTICO TÉCNICO NO LOCAL',       250,          10, 1, 'cumprido', false, true, v_dono),
    ('D2', 'rv',    'DIAGNÓSTICO TÉCNICO NO LOCAL',       250,          11, 0, 'cumprido', false, true, v_dono)
  ) as t(nome, bem, servico, mo, cumpridos, parciais, res, diaria, com_ci, payee)
  loop
    v_os := md5('e7e:os:' || r.nome)::uuid;
    v_payee := r.payee;
    v_n := r.cumpridos + r.parciais;
    if v_payee = v_dono then
      v_ini := public.agenda_somar_du(v_cur_d, 0);
      v_fim := public.agenda_somar_du(v_ini, (v_n - 1) / 2);
      v_cur_d := public.agenda_somar_du(v_fim, 2);
    else
      v_ini := public.agenda_somar_du(v_cur, 0);
      v_fim := public.agenda_somar_du(v_ini, (v_n - 1) / 2);
      v_cur := public.agenda_somar_du(v_fim, 2);
    end if;
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                       created_at, updated_at, converted_to_os_at, check_in_at, check_out_at, delivered_at, grand_total)
    values (v_os, 'OS-7E-' || r.nome, c_cli, case r.bem when 'rv' then c_rv else c_bar end, 'completed', 'approved', 'repair',
            ((v_ini - 20) + time '10:00') at time zone 'America/Sao_Paulo', ((v_fim + 1) + time '10:00') at time zone 'America/Sao_Paulo',
            ((v_ini - 14) + time '10:00') at time zone 'America/Sao_Paulo',
            case when r.com_ci then (v_ini + time '08:00') at time zone 'America/Sao_Paulo' end,
            (v_fim + time '17:00') at time zone 'America/Sao_Paulo', ((v_fim + 1) + time '10:00') at time zone 'America/Sao_Paulo', r.mo);
    if r.mo > 0 then
      insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
      values (md5('e7e:servico:' || r.nome)::uuid, v_os, null, r.servico, 'visit', 1, r.mo, r.mo, ((v_ini - 20) + time '10:00') at time zone 'America/Sao_Paulo');
    end if;
    -- o que o dono disse: só D1 e D2 (5 dias, antes do check-in)
    if r.nome in ('D1', 'D2') then
      insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, atualizado_em)
      values (v_os, 5, 'dono', ((v_ini - 5) + time '10:00') at time zone 'America/Sao_Paulo', ((v_ini - 5) + time '10:00') at time zone 'America/Sao_Paulo');
    end if;
    -- as alocações, em ordem de meio-dia a partir de v_ini
    for i in 1 .. v_n loop
      v_dia := public.agenda_somar_du(v_ini, (i - 1) / 2);
      v_res := case when i <= r.cumpridos then 'cumprido' when i <= r.cumpridos + r.parciais then 'parcial' end;
      if r.res <> 'cumprido' then
        v_res := r.res;
      end if;
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em,
                                           resultado, motivo, resultado_via, resultado_em)
      values (v_os, v_payee, v_dia, case when i % 2 = 1 then 'manha' else 'tarde' end, 'turno', 'execucao', 'publicada', 'motor',
              ((v_ini - 1) + time '16:30') at time zone 'America/Sao_Paulo',
              v_res, case when v_res in ('parcial', 'nao_cumprido') then 'estimativa' end, 'dia_feito', (v_dia + time '17:30') at time zone 'America/Sao_Paulo');
    end loop;
    -- a diária de Caio no 1º dia, ligada à OS
    if r.diaria then
      insert into public.work_shifts (id, work_profile_id, data, tipo, fracao, valor_diaria, origem, status, registrado_por, aprovado_por, aprovado_em)
      values (md5('e7e:ws:' || v_ini)::uuid, c_perf, v_ini, 'diaria', 1, 200, 'painel', 'aprovado', v_autor, v_autor, (v_ini + time '20:00') at time zone 'America/Sao_Paulo');
      insert into public.work_shift_os (shift_id, service_order_id) values (md5('e7e:ws:' || v_ini)::uuid, v_os);
    end if;
  end loop;

  -- As linhas de material das 4 fontes da compra (a 1ª fonte, m1, é a do P1): a nota e o histórico; a de balcão, com a fonte do dono.
  insert into public.material_remessas (id, nfe_chave, numero, emitida_em) values (v_nota, repeat('4', 44), '990001', date '2026-12-07');
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, remessa_id, atualizado_por)
  values (md5('e7e:material:m4')::uuid, c_os0, 'dono', 'Compressor', 1, 0, true, 'a_caminho', null, v_nota, v_autor);
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, historico, atualizado_por)
  values (md5('e7e:material:m5')::uuid, c_os0, 'dono', 'Bomba', 1, 0, true, 'comprado', null,
          jsonb_build_array(jsonb_build_object('em', '2026-12-02', 'de', 'falta', 'para', 'comprado', 'por', 'dono', 'autor', v_autor, 'trecho', 'comprei', 'nota', null)), v_autor);
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, chegou_em, atualizado_por)
  values (md5('e7e:material:m6')::uuid, c_os0, 'dono', 'Fusível', 1, 1, true, 'na_mao', 'dono', date '2026-12-03', v_autor);
  perform set_config('agenda.porta', 'off', true);
  perform set_config('agenda.hoje', '', true);
end
$f7e_p2$;
