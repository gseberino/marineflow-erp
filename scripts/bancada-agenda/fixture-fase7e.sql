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
--   P5  o prazo real das 8 OS do viés
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
