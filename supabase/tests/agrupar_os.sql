-- Prova: agrupar e desagrupar ORDENS DE SERVIÇO (migration 20261028120000_agrupar_os).
--
--   A1  caminho feliz: OS A (agendada, ASSINADA, sinal pago, técnico, 2 passos pendentes, envio do link e
--       tarefa manual + tarefa automática) + OS B (principal, aprovada: saldo pendente com cobrança, boleto
--       e lembrete agendado; pedido de compra; cotação com item ligado à peça; kit; 2 técnicos, um repetido;
--       deslocamento; comissão 5%). A nova: número, situação/data da principal, quote_status aprovado,
--       convertida, total = soma, linhas/kit/passos remapeados, técnicos sem repetir, comissão da principal
--       recalculada, payment_status parcial; recebíveis/cobrança/boleto/lembrete/compra/cotação/tarefa manual
--       MOVIDOS (status e valores iguais), item da cotação aponta para a peça NOVA; tarefa automática fica;
--       envio do link cancelado; originais canceladas, sem link, apontando para a nova, totais intactos,
--       payment_status 'unpaid', "antes" guardado (status_antes); a assinatura de A NÃO é superada;
--       reserva de estoque sem contar duas vezes; "Saldo — OS-N" pelos 990 sem título; avisos (assinaturas,
--       situações, data, saldo, chegada no barco — que fica na original); auditoria
--   A2–A4 sem recebível nenhum não lança saldo; missão aguardando resposta vai e volta; recebíveis cobrindo
--       o total não lançam saldo; principal aguardando sinal: a nova herda, o sinal pago a aprova e o
--       desagrupar devolve a original aprovada
--   B01–B23 recusas (a mensagem certa e NADA muda): cliente, embarcação, nota fiscal, fatura, comissão,
--       item de nota de entrada, agrupada de novo, mais de 10, deslocamento em duas, total desatualizado,
--       total esperado errado, técnico (sem cargo), orçamento (rascunho), em andamento, hora apontada,
--       despesa, passo iniciado, foto, baixa de estoque, repasse do cartão, uma só, serviço com situação de campo
--   B22 baixa ESTORNADA (OS que voltou de concluída) não conta como execução: agrupa
--   C1–C4 guardas: origem agrupada não muda de situação nem é apagada ("Esta OS foi agrupada"); recebível
--       na origem agrupada recusado ("Esta OS foi agrupada em"); merged_into_id só pelas funções ("OS")
--   D1–D3 portas: técnico/inativo/sem autor 42501; porta pública sem sessão pede login e o
--       document_number_seq não anda; privilégios
--   E1–E8 desagrupar: o A1 volta inteiro (registros, situação, link, payment_status, reservas, assinatura
--       intacta, envio de volta à fila; o Pix do saldo conciliado e o lembrete criados na agrupada seguem o
--       recebível; o saldo lançado é cancelado); de novo recusa; depois de hora apontada recusa; com
--       recebível novo recusa; técnico recusa; lançamento/anotação do extrato na agrupada recusa; saldo
--       lançado com pagamento recusa
--   F1–F3 cancelar a agrupada pelo caminho normal (update e cascata) recusa "Desagrupar"; depois de
--       começar a execução cancela; a já desagrupada não reabre ("desagrupada")
--   G1  leitura os_para_agrupar: elegível/motivo (mesma mensagem do agrupar), agrupados_ativos com
--       pode_desagrupar; a leitura de orçamentos não lista agrupamento de OS
--
-- ═══ COMO RODAR ═══ (só com OK nomeado; DEPOIS da migration aplicada — o arquivo usa as funções dela)
--
--   npx supabase@2.111.0 db query --linked -f supabase/tests/agrupar_os.sql --output json
--   (a partir do repositório principal: o worktree não é linkado)
--
-- Seguro em produção: usuários, clientes, barcos, produto e OS de teste criados aqui (números OS-9xxxxx
-- livres); as agrupadas recebem números fictícios OS-T… passados direto a _agrupar_os_montar, que assim NÃO
-- gastam o document_number_seq; a porta pública agrupar_os só roda no D2, onde falha antes de numerar (e o
-- D2 confere isso). Os envios de WhatsApp agendados nascem e morrem dentro da transação: nada sai. Termina
-- em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ids (nome text primary key, id uuid) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop')
$$;

create function pg_temp._id(p_nome text) returns uuid language sql stable as $$
  select id from _ids where nome = p_nome
$$;

create function pg_temp._se(p_ok boolean, p_nome text) returns text language sql immutable as $$
  select case when coalesce(p_ok, false) then null else p_nome end
$$;

create function pg_temp._usuario(p_role text, p_ativo boolean default true) returns uuid language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste agrupar OS (' || p_role || ')', 'teste-agrupar-os-' || v_id || '@teste.invalido', p_role, p_ativo);
  return v_id;
end $$;

create function pg_temp._cliente() returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Agrupar OS ' || pg_temp._letras(6))
  returning id into v_id;
  return v_id;
end $$;

create function pg_temp._barco(p_cli uuid) returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.vessels (client_id, name) values (p_cli, 'Barco' || pg_temp._letras(8)) returning id into v_id;
  return v_id;
end $$;

create function pg_temp._produto() returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.products (name, cost_price, sale_price)
  values ('Peça teste agrupar OS ' || pg_temp._letras(6), 40, 75) returning id into v_id;
  return v_id;
end $$;

create function pg_temp._numero_livre() returns text language plpgsql as $$
declare
  v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders where service_order_number = 'OS-' || v_num) loop
    v_num := v_num + 1;
  end loop;
  return 'OS-' || v_num;
end $$;

create function pg_temp._numero_agrupado() returns text language sql volatile as $$
  select 'OS-T' || upper(pg_temp._letras(6))
$$;

-- OS (já convertida) sem linhas
create function pg_temp._os_vazia(p_cli uuid, p_ves uuid, p_status text default 'approved', p_criado_em timestamptz default null)
returns uuid language plpgsql as $$
declare
  v_os uuid;
begin
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, converted_to_os_at, created_at)
  values (pg_temp._numero_livre(), p_cli, p_ves, p_status,
          case when p_status = 'draft' then 'draft' else 'approved' end,
          case when p_status = 'draft' then null else now() end,
          coalesce(p_criado_em, clock_timestamp()))
  returning id into v_os;
  return v_os;
end $$;

create function pg_temp._servico(p_os uuid, p_nome text, p_qtd numeric, p_preco numeric, p_criado_em timestamptz default null)
returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, discount_pct, discount_amount,
                                             created_at, updated_at)
  values (p_os, p_nome, 'hour', p_qtd, p_preco, round(p_qtd * p_preco, 2), 0, 0,
          coalesce(p_criado_em, clock_timestamp()), coalesce(p_criado_em, clock_timestamp()))
  returning id into v_id;
  return v_id;
end $$;

-- OS comum de teste: 1 serviço (2 h × R$ 150), totais pelo banco
create function pg_temp._os(p_cli uuid, p_ves uuid, p_status text default 'approved')
returns uuid language plpgsql as $$
declare
  v_os uuid;
begin
  v_os := pg_temp._os_vazia(p_cli, p_ves, p_status);
  perform pg_temp._servico(v_os, 'Serviço de teste', 2, 150);
  perform public.recalc_so_totals(v_os);
  return v_os;
end $$;

create function pg_temp._dupla() returns uuid[] language plpgsql as $$
declare
  v_cli uuid;
  v_ves uuid;
  v_a uuid;
  v_b uuid;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_a := pg_temp._os(v_cli, v_ves);
  v_b := pg_temp._os(v_cli, v_ves);
  return array[v_a, v_b];
end $$;

create function pg_temp._erro_montar(p_ids uuid[], p_base uuid, p_numero text, p_autor uuid, p_total numeric)
returns text language plpgsql as $$
begin
  perform public._agrupar_os_montar(p_ids, p_base, p_numero, p_autor, p_total);
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

create function pg_temp._erro_desfazer(p_agrupado uuid, p_autor uuid) returns text language plpgsql as $$
begin
  perform public._desagrupar_os_desfazer(p_agrupado, p_autor);
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

create function pg_temp._erro_sql(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

create function pg_temp._retrato(p_ids uuid[]) returns text language sql stable as $$
  select string_agg(concat_ws('/', so.id, so.status, coalesce(so.quote_status, '-'), coalesce(so.share_token::text, '-'),
                              coalesce(so.merged_into_id::text, '-'), coalesce(so.grand_total::text, '-'),
                              coalesce(so.cancelled_at::text, '-'), coalesce(so.payment_status, '-')),
                    ' | ' order by so.id)
    from public.service_orders so where so.id = any(p_ids)
$$;

create function pg_temp._bloqueio(p_teste text, p_ids uuid[], p_base uuid, p_autor uuid, p_total numeric, p_trecho text)
returns void language plpgsql as $$
declare
  v_numero text := pg_temp._numero_agrupado();
  v_antes text;
  v_depois text;
  v_erro text;
  v_criou boolean;
begin
  v_antes := pg_temp._retrato(p_ids);
  v_erro := pg_temp._erro_montar(p_ids, p_base, v_numero, p_autor, p_total);
  v_depois := pg_temp._retrato(p_ids);
  v_criou := exists (select 1 from public.service_orders where service_order_number = v_numero);
  insert into _resultado values (p_teste,
    v_erro is not null and strpos(v_erro, p_trecho) > 0 and v_antes is not distinct from v_depois and not v_criou,
    coalesce(v_erro, 'sem erro: agrupou')
      || case when v_antes is distinct from v_depois then ' | AS ORIGENS MUDARAM' else '' end
      || case when v_criou then ' | A AGRUPADA NASCEU' else '' end);
end $$;

insert into _ids values
  ('admin', pg_temp._usuario('admin')),
  ('financeiro', pg_temp._usuario('financial')),
  ('tecnico', pg_temp._usuario('technician')),
  ('tecnico2', pg_temp._usuario('technician')),
  ('admin_inativo', pg_temp._usuario('admin', false));

-- ═══ A1 caminho feliz ═══════════════════════════════════════════════════════════════════════
do $$
declare
  v_admin uuid := pg_temp._id('admin');
  v_t1 uuid := pg_temp._id('tecnico');
  v_t2 uuid := pg_temp._id('tecnico2');
  v_cli uuid;
  v_ves uuid;
  v_prod uuid;
  v_a uuid;
  v_b uuid;
  v_sa uuid;
  v_sb uuid;
  v_pb uuid;
  v_token_a uuid;
  v_total_a numeric;
  v_total_b numeric;
  v_sinal uuid;
  v_saldo uuid;
  v_cobr uuid;
  v_boleto uuid;
  v_lembrete uuid;
  v_envio_link uuid;
  v_tarefa uuid;
  v_tarefa_auto uuid;
  v_po uuid;
  v_qr uuid;
  v_qri uuid;
  v_assin uuid;
  v_agenda timestamptz := date_trunc('minute', now() + interval '3 days');
  r jsonb;
  v_novo uuid;
  v_grupo uuid;
  n public.service_orders;
  v_reserva_antes numeric;
  v_reserva_depois numeric;
  v_falhas text;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_prod := pg_temp._produto();

  -- A: agendada, 1 serviço (2 × 150) com 2 passos pendentes, 1 peça (2 × 75), técnico T1, sinal pago 100,
  --    envio do link pendente, tarefa manual e tarefa automática; ASSINADA (depois das linhas)
  v_a := pg_temp._os_vazia(v_cli, v_ves, 'scheduled', now() - interval '2 hours');
  -- chegada no barco registrada (visita de levantamento): não recusa, fica na original e o retorno avisa
  update public.service_orders set scheduled_start_at = v_agenda, scheduled_end_at = v_agenda + interval '2 hours',
         problem_description = 'Revisar o quadro elétrico', commission_rate = 3, check_in_at = now() - interval '1 day'
   where id = v_a;
  v_sa := pg_temp._servico(v_a, 'A1 Revisão do quadro', 2, 150, now() - interval '2 hours');
  insert into public.service_order_steps (service_order_id, service_order_service_id, seq, title, status)
  values (v_a, v_sa, 1, 'Passo A1', 'pending'), (v_a, v_sa, 2, 'Passo A2', 'pending');
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, source, created_at, updated_at)
  values (v_a, v_prod, 2, 40, 75, 80, 150, 'manual', now() - interval '2 hours' + interval '1 second',
          now() - interval '2 hours' + interval '1 second');
  perform public.recalc_so_totals(v_a);
  insert into public.service_order_technicians (service_order_id, user_id) values (v_a, v_t1);
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, paid_amount,
                                  balance_amount, status, is_deposit)
  values (v_cli, v_a, 'Teste agrupar OS: sinal pago', current_date, current_date, 100, 100, 0, 'paid', true)
  returning id into v_sinal;
  insert into public.whatsapp_scheduled_sends (target_kind, service_order_id, client_id, phone, message, scheduled_at, next_run_at, status)
  values ('service_order', v_a, v_cli, '550000000000', 'Teste agrupar OS: link da OS', now() + interval '1 day',
          now() + interval '1 day', 'pending')
  returning id into v_envio_link;
  insert into public.agenda_tasks (title, status, source, related_entity_type, related_entity_id, client_id)
  values ('Teste agrupar OS: visita manual', 'pending', 'manual', 'service_order', v_a, v_cli)
  returning id into v_tarefa;
  insert into public.agenda_tasks (title, status, source, related_entity_type, related_entity_id, client_id, automation_key)
  values ('Teste agrupar OS: comprar 1 item', 'pending', 'automation', 'service_order', v_a, v_cli, 'r16:so:' || v_a)
  returning id into v_tarefa_auto;
  select share_token into v_token_a from public.service_orders where id = v_a;
  insert into public.service_order_signatures (service_order_id, share_token, accepted_name, document_hash)
  values (v_a, v_token_a, 'Cliente Teste', 'hash-teste') returning id into v_assin;
  update public.service_orders set signed_at = now(), signed_by_name = 'Cliente Teste' where id = v_a;

  -- B (principal): aprovada, comissão 5%, condição em texto, deslocamento 150/30 km; 1 serviço (3 × 180) +
  --    peça manual (2 × 75) + peça do kit do serviço (1 × 200); técnicos T1 e T2; saldo 400 pendente com
  --    cobrança, boleto e lembrete; pedido de compra; cotação com item ligado à peça manual
  v_b := pg_temp._os_vazia(v_cli, v_ves, 'approved', now() - interval '1 hour');
  update public.service_orders
     set travel_cost_total = 150, travel_distance_km = 30, commission_rate = 5,
         payment_condition_preset_id = null, payment_conditions = '50% na aprovação, 50% na entrega',
         problem_description = 'Instalar o inversor'
   where id = v_b;
  v_sb := pg_temp._servico(v_b, 'B1 Instalação do inversor', 3, 180, now() - interval '1 hour');
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, source, created_at, updated_at)
  values (v_b, v_prod, 2, 40, 75, 80, 150, 'manual', now() - interval '1 hour' + interval '1 second',
          now() - interval '1 hour' + interval '1 second')
  returning id into v_pb;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, source, service_order_service_id, created_at, updated_at)
  values (v_b, v_prod, 1, 100, 200, 100, 200, 'kit', v_sb, now() - interval '1 hour' + interval '2 seconds',
          now() - interval '1 hour' + interval '2 seconds');
  perform public.recalc_so_totals(v_b);
  insert into public.service_order_technicians (service_order_id, user_id) values (v_b, v_t1), (v_b, v_t2);
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, balance_amount, status)
  values (v_cli, v_b, 'Teste agrupar OS: saldo', current_date, current_date + 10, 400, 400, 'pending')
  returning id into v_saldo;
  insert into public.collections (service_order_id, receivable_id, client_id, amount, due_date, status)
  values (v_b, v_saldo, v_cli, 400, current_date + 10, 'pending') returning id into v_cobr;
  insert into public.bank_charges (receivable_id, service_order_id, client_id, provider, kind, amount, due_date, status)
  values (v_saldo, v_b, v_cli, 'teste', 'pix', 400, current_date + 10, 'pending') returning id into v_boleto;
  insert into public.whatsapp_scheduled_sends (target_kind, service_order_id, receivable_id, client_id, phone, message,
                                               scheduled_at, next_run_at, status)
  values ('receivable', v_b, v_saldo, v_cli, '550000000000', 'Teste agrupar OS: lembrete de cobrança',
          now() + interval '5 days', now() + interval '5 days', 'pending')
  returning id into v_lembrete;
  insert into public.purchase_orders (po_number, status, service_order_id)
  values ('PO-TESTE-' || upper(pg_temp._letras(8)), 'draft', v_b) returning id into v_po;
  insert into public.quote_requests (code, service_order_id, status)
  values ('COT-TESTE-' || upper(pg_temp._letras(8)), v_b, 'open') returning id into v_qr;
  insert into public.quote_request_items (quote_request_id, product_id, description, quantity, service_order_part_id)
  values (v_qr, v_prod, 'Peça cotada', 2, v_pb) returning id into v_qri;

  select grand_total into v_total_a from public.service_orders where id = v_a;
  select grand_total into v_total_b from public.service_orders where id = v_b;
  select reserved_quantity into v_reserva_antes from public.products where id = v_prod;

  r := public._agrupar_os_montar(array[v_a, v_b], v_b, pg_temp._numero_agrupado(), v_admin, v_total_a + v_total_b);
  v_novo := (r ->> 'service_order_id')::uuid;
  v_grupo := (r ->> 'agrupamento_id')::uuid;
  select * into n from public.service_orders where id = v_novo;
  select reserved_quantity into v_reserva_depois from public.products where id = v_prod;

  v_falhas := concat_ws(', ',
    pg_temp._se(n.grand_total = v_total_a + v_total_b and (r ->> 'total_geral')::numeric = n.grand_total, 'total'),
    pg_temp._se(n.status = 'approved' and n.quote_status = 'approved' and n.converted_to_os_at is not null
                and n.merged_into_id is null and n.client_id = v_cli and n.vessel_id = v_ves
                and n.scheduled_start_at is null and n.signed_at is null and not n.requires_resignature, 'situação da nova'),
    pg_temp._se((select count(*) from public.service_order_services x where x.service_order_id = v_novo) = 2
                and (r ->> 'servicos')::int = 2, 'serviços'),
    pg_temp._se((select count(*) from public.service_order_parts p where p.service_order_id = v_novo) = 3
                and (r ->> 'pecas')::int = 3, 'peças'),
    pg_temp._se(exists (select 1 from public.service_order_parts p
                          join public.service_order_services x on x.id = p.service_order_service_id
                         where p.service_order_id = v_novo and p.source = 'kit'
                           and x.service_order_id = v_novo and x.name_snapshot = 'B1 Instalação do inversor'), 'kit'),
    pg_temp._se((select count(*) from public.service_order_steps st
                   join public.service_order_services x on x.id = st.service_order_service_id
                  where st.service_order_id = v_novo and x.service_order_id = v_novo
                    and x.name_snapshot = 'A1 Revisão do quadro' and st.status = 'pending') = 2
                and (select count(*) from public.service_order_steps st where st.service_order_id = v_a) = 2, 'passos copiados'),
    pg_temp._se((select count(*) from public.service_order_technicians t where t.service_order_id = v_novo) = 2
                and (r ->> 'tecnicos')::int = 2
                and (select count(*) from public.service_order_technicians t where t.service_order_id = v_b) = 2, 'técnicos'),
    pg_temp._se(n.commission_rate = 5 and n.commission_amount = round(n.grand_total * 5 / 100, 2)
                and n.payment_conditions = '50% na aprovação, 50% na entrega'
                and n.travel_cost_total = 150, 'principal manda'),
    pg_temp._se(n.payment_status = 'partially_paid' and r ->> 'payment_status' = 'partially_paid', 'payment_status da nova'),
    pg_temp._se((select count(*) from public.receivables x where x.service_order_id = v_novo) = 3
                and exists (select 1 from public.receivables x where x.id = v_sinal and x.status = 'paid' and x.amount = 100
                              and x.paid_amount = 100 and x.is_deposit)
                and exists (select 1 from public.receivables x where x.id = v_saldo and x.status = 'pending' and x.amount = 400)
                and (r ->> 'recebiveis_movidos')::int = 2, 'recebíveis movidos'),
    -- 1.490 de total, 500 em recebíveis: os 990 sem título viram "Saldo — OS-T…" pendente, vencendo na conclusão
    pg_temp._se(exists (select 1 from public.receivables x
                          join public.orcamento_agrupamentos g on g.saldo_criado_id = x.id and g.id = v_grupo
                         where x.service_order_id = v_novo and x.status = 'pending' and x.amount = n.grand_total - 500
                           and x.balance_amount = n.grand_total - 500 and coalesce(x.paid_amount, 0) = 0
                           and x.due_on_completion and not x.is_deposit
                           and x.description = 'Saldo — ' || n.service_order_number)
                and (r ->> 'saldo_lancado')::numeric = n.grand_total - 500
                and (select sum(x.amount) from public.receivables x where x.service_order_id = v_novo) = n.grand_total, 'saldo sem título'),
    pg_temp._se(exists (select 1 from public.collections x where x.id = v_cobr and x.service_order_id = v_novo and x.status = 'pending')
                and exists (select 1 from public.bank_charges x where x.id = v_boleto and x.service_order_id = v_novo)
                and (r ->> 'cobrancas_movidas')::int = 1, 'cobrança/boleto'),
    pg_temp._se(exists (select 1 from public.whatsapp_scheduled_sends w where w.id = v_lembrete and w.service_order_id = v_novo
                          and w.status = 'pending')
                and exists (select 1 from public.whatsapp_scheduled_sends w where w.id = v_envio_link and w.status = 'cancelled'
                              and w.last_error = 'Cancelado: OS agrupada em ' || n.service_order_number)
                and (r ->> 'envios_cancelados')::int = 1, 'envios'),
    pg_temp._se(exists (select 1 from public.purchase_orders x where x.id = v_po and x.service_order_id = v_novo)
                and exists (select 1 from public.quote_requests x where x.id = v_qr and x.service_order_id = v_novo)
                and exists (select 1 from public.quote_request_items i join public.service_order_parts p on p.id = i.service_order_part_id
                             where i.id = v_qri and p.service_order_id = v_novo and p.source = 'manual'), 'compra/cotação'),
    pg_temp._se(exists (select 1 from public.agenda_tasks t where t.id = v_tarefa and t.related_entity_id = v_novo)
                and exists (select 1 from public.agenda_tasks t where t.id = v_tarefa_auto and t.related_entity_id = v_a
                              and t.status = 'pending')
                and (r ->> 'tarefas_movidas')::int = 1, 'tarefas'),
    pg_temp._se((select count(*) from public.service_orders so
                  where so.id in (v_a, v_b) and so.status = 'cancelled' and so.share_token is null and so.merged_into_id = v_novo
                    and so.payment_status = 'unpaid' and so.cancellation_reason like 'Agrupada em OS-T%') = 2
                and (select grand_total from public.service_orders where id = v_a) = v_total_a
                and (select grand_total from public.service_orders where id = v_b) = v_total_b, 'origens'),
    pg_temp._se(exists (select 1 from public.service_order_signatures g where g.id = v_assin and g.superseded_at is null)
                and exists (select 1 from public.service_orders so where so.id = v_a and so.signed_at is not null
                              and not so.requires_resignature), 'assinatura intacta'),
    pg_temp._se(exists (select 1 from public.orcamento_agrupamentos g where g.id = v_grupo and g.tipo = 'os' and g.agrupado_id = v_novo)
                and exists (select 1 from public.orcamento_agrupamento_origens o where o.agrupamento_id = v_grupo and o.origem_id = v_a
                              and o.status_antes = 'scheduled' and o.share_token_antes = v_token_a and o.ordem = 1)
                and exists (select 1 from public.orcamento_agrupamento_origens o where o.agrupamento_id = v_grupo and o.origem_id = v_b
                              and o.status_antes = 'approved' and o.ordem = 2), '"antes" guardado'),
    pg_temp._se(v_reserva_antes = 5 and v_reserva_depois = 5, 'reserva (antes ' || coalesce(v_reserva_antes::text, 'null')
                || ', depois ' || coalesce(v_reserva_depois::text, 'null') || ')'),
    pg_temp._se(exists (select 1 from jsonb_array_elements_text(r -> 'avisos') a where a like 'As assinaturas ficaram nas OS originais%')
                and exists (select 1 from jsonb_array_elements_text(r -> 'avisos') a where a like '%situações diferentes%')
                and exists (select 1 from jsonb_array_elements_text(r -> 'avisos') a where a like 'Tinha atendimento marcado%')
                and exists (select 1 from jsonb_array_elements_text(r -> 'avisos') a where a like '%ganhou o recebível "Saldo — %')
                and exists (select 1 from jsonb_array_elements_text(r -> 'avisos') a where a like 'Já houve chegada no barco registrada%')
                and n.check_in_at is null, 'avisos'),
    pg_temp._se((select count(*) from public.audit_log l where l.table_name = 'service_orders' and l.action = 'cancel'
                  and l.triggered_by_id = v_novo and l.record_id in (v_a, v_b)) = 2, 'auditoria'));

  insert into _ids values ('a1_saldo_criado', (select g.saldo_criado_id from public.orcamento_agrupamentos g where g.id = v_grupo));
  insert into _ids values ('a1_a', v_a), ('a1_b', v_b), ('a1_novo', v_novo), ('a1_prod', v_prod), ('a1_assin', v_assin),
                          ('a1_sinal', v_sinal), ('a1_saldo', v_saldo), ('a1_lembrete', v_lembrete), ('a1_envio', v_envio_link),
                          ('a1_tarefa', v_tarefa), ('a1_po', v_po), ('a1_qri', v_qri), ('a1_pb', v_pb), ('a1_cobr', v_cobr);
  insert into _resultado values ('A1 caminho feliz: nova OS com situação/data da principal, dinheiro/compras/tarefa movidos, linhas/passos copiados, assinatura intacta, reserva, avisos',
    v_falhas = '',
    case when v_falhas = '' then '' else 'falhou: ' || v_falhas || ' | ' end
    || 'nova=' || coalesce(n.service_order_number, 'null') || ' total=' || coalesce(n.grand_total::text, 'null')
    || ' avisos=' || coalesce((r -> 'avisos')::text, 'null'));
exception when others then
  insert into _resultado values ('A1 caminho feliz: nova OS com situação/data da principal, dinheiro/compras/tarefa movidos, linhas/passos copiados, assinatura intacta, reserva, avisos',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ A2–A4 saldo, missão aguardando resposta, sinal pendente ════════════════════════════════
do $$
declare
  v uuid[]; v_cli uuid; v_m uuid; r jsonb; v_g uuid; v_falhas text;
begin
  -- Nenhuma com recebível: nada é lançado (a conclusão gera o plano da condição). Missão aguardando resposta vai junto.
  v := pg_temp._dupla();
  select client_id into v_cli from public.service_orders where id = v[1];
  insert into public.ai_followup_missions (objetivo, contraparte_tipo, contraparte_phone, contraparte_label, origem_tipo,
                                           service_order_id, status)
  values ('Teste agrupar OS: aguardando o cliente', 'client', '550000000000', 'Cliente teste', 'manual', v[2], 'waiting_reply')
  returning id into v_m;
  r := public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  v_g := (r ->> 'service_order_id')::uuid;
  v_falhas := concat_ws(', ',
    pg_temp._se(not exists (select 1 from public.receivables x where x.service_order_id = v_g)
                and (r -> 'saldo_lancado') = 'null'::jsonb
                and exists (select 1 from public.orcamento_agrupamentos g where g.agrupado_id = v_g and g.saldo_criado_id is null)
                and not exists (select 1 from jsonb_array_elements_text(r -> 'avisos') a where a like '%Saldo —%'), 'sem saldo'),
    pg_temp._se(exists (select 1 from public.ai_followup_missions x where x.id = v_m and x.service_order_id = v_g
                          and x.status = 'waiting_reply'), 'missão aguardando resposta'));
  perform public._desagrupar_os_desfazer(v_g, pg_temp._id('admin'));
  v_falhas := concat_ws(', ', nullif(v_falhas, ''),
    pg_temp._se(exists (select 1 from public.ai_followup_missions x where x.id = v_m and x.service_order_id = v[2]), 'missão de volta'));
  insert into _resultado values ('A2 sem recebível em nenhuma: nada lançado; missão aguardando resposta vai e volta',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || r::text end);

  -- Recebíveis cobrindo o total (300 + 300): nenhum saldo
  v := pg_temp._dupla();
  select client_id into v_cli from public.service_orders where id = v[1];
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, paid_amount,
                                  balance_amount, status, is_deposit)
  values (v_cli, v[1], 'Teste agrupar OS: à vista pago', current_date, current_date, 300, 300, 0, 'paid', true),
         (v_cli, v[2], 'Teste agrupar OS: na entrega', current_date, current_date + 10, 300, 0, 300, 'pending', false);
  r := public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  v_g := (r ->> 'service_order_id')::uuid;
  insert into _resultado values ('A3 recebíveis cobrindo o total: nenhum saldo lançado',
    (select count(*) from public.receivables x where x.service_order_id = v_g) = 2 and (r -> 'saldo_lancado') = 'null'::jsonb
    and (r ->> 'payment_status') = 'partially_paid',
    r::text);
exception when others then
  insert into _resultado values ('A2/A3 saldo e missão', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[]; v_cli uuid; v_dep uuid; r jsonb; v_g uuid; v_falhas text; v_saldo uuid;
begin
  -- Principal aguardando o sinal (100 de 600, pendente): a nova herda; o sinal pago NA agrupada a aprova; o
  -- desagrupar devolve a original aprovada (com o sinal pago), não "Aguardando sinal"
  v := pg_temp._dupla();
  select client_id into v_cli from public.service_orders where id = v[1];
  update public.service_orders set quote_status = 'awaiting_deposit' where id = v[1];
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, paid_amount,
                                  balance_amount, status, is_deposit)
  values (v_cli, v[1], 'Teste agrupar OS: sinal pendente', current_date, current_date + 3, 100, 0, 100, 'pending', true)
  returning id into v_dep;
  r := public._agrupar_os_montar(v, v[1], pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  v_g := (r ->> 'service_order_id')::uuid;
  select g.saldo_criado_id into v_saldo from public.orcamento_agrupamentos g where g.agrupado_id = v_g;
  v_falhas := concat_ws(', ',
    pg_temp._se(exists (select 1 from public.service_orders so where so.id = v_g and so.quote_status = 'awaiting_deposit'), 'nova aguardando sinal'),
    pg_temp._se(exists (select 1 from public.receivables x where x.id = v_saldo and x.amount = 500 and x.status = 'pending'), 'saldo de 500'));
  update public.receivables set status = 'paid', paid_amount = 100, balance_amount = 0 where id = v_dep;
  v_falhas := concat_ws(', ', nullif(v_falhas, ''),
    pg_temp._se(exists (select 1 from public.service_orders so where so.id = v_g and so.quote_status = 'approved'), 'sinal pago aprova a nova'));
  perform public._desagrupar_os_desfazer(v_g, pg_temp._id('admin'));
  v_falhas := concat_ws(', ', nullif(v_falhas, ''),
    pg_temp._se(exists (select 1 from public.service_orders so where so.id = v[1] and so.quote_status = 'approved'
                          and so.merged_into_id is null and so.payment_status = 'paid'), 'original aprovada'),
    pg_temp._se(exists (select 1 from public.receivables x where x.id = v_dep and x.service_order_id = v[1] and x.status = 'paid'), 'sinal de volta'),
    pg_temp._se(exists (select 1 from public.receivables x where x.id = v_saldo and x.status = 'cancelled'), 'saldo cancelado'));
  insert into _resultado values ('A4 principal aguardando sinal: a nova herda, o sinal pago a aprova e o desagrupar devolve a original aprovada',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || r::text end);
exception when others then
  insert into _resultado values ('A4 principal aguardando sinal: a nova herda, o sinal pago a aprova e o desagrupar devolve a original aprovada',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ B recusas ══════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_cli uuid; v_cli2 uuid; v_ves uuid; a uuid; b uuid;
begin
  v_cli := pg_temp._cliente(); v_cli2 := pg_temp._cliente();
  a := pg_temp._os(v_cli, pg_temp._barco(v_cli));
  b := pg_temp._os(v_cli2, pg_temp._barco(v_cli2));
  perform pg_temp._bloqueio('B01 cliente diferente ("mesmo cliente")', array[a, b], null, pg_temp._id('admin'), null, 'mesmo cliente');
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._os(v_cli, v_ves);
  b := pg_temp._os(v_cli, pg_temp._barco(v_cli));
  perform pg_temp._bloqueio('B02 embarcação diferente ("mesma embarcação")', array[a, b], null, pg_temp._id('admin'), null, 'mesma embarcação');
exception when others then
  insert into _resultado values ('B01/B02 cliente/embarcação', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[]; v_cli uuid;
begin
  v := pg_temp._dupla();
  select client_id into v_cli from public.service_orders where id = v[2];
  insert into public.issued_fiscal_documents (document_type, origin_type, origin_id, client_id, status)
  values ('nfse', 'service_order', v[2], v_cli, 'authorized');
  perform pg_temp._bloqueio('B03 nota fiscal autorizada ("nota fiscal")', v, null, pg_temp._id('admin'), null, 'nota fiscal');

  v := pg_temp._dupla();
  select client_id into v_cli from public.service_orders where id = v[2];
  insert into public.invoices (invoice_number, service_order_id, client_id, issue_date, due_date, status)
  values ('FAT-TESTE-' || upper(pg_temp._letras(8)), v[2], v_cli, current_date, current_date + 10, 'draft');
  perform pg_temp._bloqueio('B04 fatura ("fatura")', v, null, pg_temp._id('admin'), null, 'fatura');

  v := pg_temp._dupla();
  insert into public.commissions (service_order_id, user_id, amount, status) values (v[2], pg_temp._id('admin'), 10, 'pending');
  perform pg_temp._bloqueio('B05 comissão lançada ("comissão lançada")', v, null, pg_temp._id('admin'), null, 'comissão lançada');

  v := pg_temp._dupla();
  insert into public.fiscal_note_items (service_order_id, description, quantity) values (v[2], 'Item de nota teste', 1);
  perform pg_temp._bloqueio('B06 item de nota de entrada ("item de nota de entrada")', v, null, pg_temp._id('admin'), null, 'item de nota de entrada');
exception when others then
  insert into _resultado values ('B03–B06 nota/fatura/comissão/item de nota', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[]; v_cli uuid; v_ves uuid; c uuid; v_ids uuid[] := '{}'; i integer;
begin
  v := pg_temp._dupla();
  select client_id, vessel_id into v_cli, v_ves from public.service_orders where id = v[1];
  c := pg_temp._os(v_cli, v_ves);
  perform public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  perform pg_temp._bloqueio('B07 origem já agrupada ("já foi agrupada em")', array[v[1], c], null, pg_temp._id('admin'), null, 'já foi agrupada em');

  v_cli := pg_temp._cliente(); v_ves := pg_temp._barco(v_cli);
  for i in 1..11 loop v_ids := v_ids || pg_temp._os(v_cli, v_ves); end loop;
  perform pg_temp._bloqueio('B08 mais de 10 ("no máximo 10")', v_ids, null, pg_temp._id('admin'), null, 'no máximo 10');

  v := pg_temp._dupla();
  update public.service_orders set travel_cost_total = 80, travel_distance_km = 15 where id = any(v);
  perform public.recalc_so_totals(v[1]); perform public.recalc_so_totals(v[2]);
  perform pg_temp._bloqueio('B09 deslocamento em duas ("deslocamento")', v, null, pg_temp._id('admin'), null, 'deslocamento');

  v := pg_temp._dupla();
  update public.service_orders set grand_total = grand_total + 7 where id = v[2];
  perform pg_temp._bloqueio('B10 total gravado desatualizado ("desatualizado")', v, null, pg_temp._id('admin'), null, 'desatualizado');

  v := pg_temp._dupla();
  perform pg_temp._bloqueio('B11 total esperado diferente ("mudaram")', v, null, pg_temp._id('admin'),
    (select sum(grand_total) + 1 from public.service_orders where id = any(v)), 'mudaram');

  v := pg_temp._dupla();
  perform pg_temp._bloqueio('B12 técnico não agrupa (42501)', v, null, pg_temp._id('tecnico'), null, '42501');

  v_cli := pg_temp._cliente(); v_ves := pg_temp._barco(v_cli);
  perform pg_temp._bloqueio('B13 orçamento em rascunho ("ainda é um orçamento")',
    array[pg_temp._os(v_cli, v_ves), pg_temp._os(v_cli, v_ves, 'draft')], null, pg_temp._id('admin'), null, 'ainda é um orçamento');

  v_cli := pg_temp._cliente(); v_ves := pg_temp._barco(v_cli);
  perform pg_temp._bloqueio('B14 em andamento ("já começou a ser executada (está em andamento)")',
    array[pg_temp._os(v_cli, v_ves), pg_temp._os(v_cli, v_ves, 'in_progress')], null, pg_temp._id('admin'), null,
    'já começou a ser executada (está em andamento). Agrupar só junta OS que ainda não começaram');
exception when others then
  insert into _resultado values ('B07–B14', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[]; v_prod uuid;
begin
  v := pg_temp._dupla();
  insert into public.time_entries (service_order_id, technician_user_id, started_at, ended_at, duration_minutes)
  values (v[2], pg_temp._id('tecnico'), now() - interval '1 hour', now(), 60);
  perform pg_temp._bloqueio('B15 hora apontada ("hora apontada")', v, null, pg_temp._id('admin'), null, 'hora apontada');

  v := pg_temp._dupla();
  insert into public.service_order_expenses (service_order_id, category, description, amount)
  values (v[2], 'material', 'Teste agrupar OS: despesa', 30);
  perform pg_temp._bloqueio('B16 despesa ("despesa lançada")', v, null, pg_temp._id('admin'), null, 'despesa lançada');

  v := pg_temp._dupla();
  insert into public.service_order_steps (service_order_id, seq, title, status, started_at)
  values (v[2], 1, 'Passo iniciado', 'in_progress', now());
  perform pg_temp._bloqueio('B17 passo iniciado ("passo do roteiro")', v, null, pg_temp._id('admin'), null, 'passo do roteiro');

  v := pg_temp._dupla();
  insert into public.service_order_photos (service_order_id, storage_path) values (v[2], 'teste/agrupar-os.jpg');
  perform pg_temp._bloqueio('B18 foto de campo ("foto de campo")', v, null, pg_temp._id('admin'), null, 'foto de campo');

  v := pg_temp._dupla();
  v_prod := pg_temp._produto();
  insert into public.inventory_movements (product_id, movement_type, quantity_delta, reference_type, reference_id)
  values (v_prod, 'purchase', 5, 'manual_entry', null);
  insert into public.inventory_movements (product_id, movement_type, quantity_delta, reference_type, reference_id)
  values (v_prod, 'service_order_usage', -1, 'service_order', v[2]);
  perform pg_temp._bloqueio('B19 baixa de estoque ("baixa de estoque")', v, null, pg_temp._id('admin'), null, 'baixa de estoque');

  v := pg_temp._dupla();
  update public.service_orders set card_fee_passthrough_enabled = true where id = v[2];
  perform public.recalc_so_totals(v[2]);
  perform pg_temp._bloqueio('B20 repasse da taxa do cartão ("taxa do cartão")', v, null, pg_temp._id('admin'), null, 'taxa do cartão');

  v := pg_temp._dupla();
  perform pg_temp._bloqueio('B21 uma OS só ("pelo menos 2")', array[v[1]], null, pg_temp._id('admin'), null, 'pelo menos 2');

  v := pg_temp._dupla();
  update public.service_order_services set field_status = 'feito' where service_order_id = v[2];
  perform pg_temp._bloqueio('B23 serviço com situação de campo ("serviço com situação de campo")', v, null, pg_temp._id('admin'), null,
    'serviço com situação de campo');
exception when others then
  insert into _resultado values ('B15–B21', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[]; v_prod uuid; v_baixa uuid; v_erro text;
begin
  v := pg_temp._dupla();
  v_prod := pg_temp._produto();
  insert into public.inventory_movements (product_id, movement_type, quantity_delta, reference_type, reference_id)
  values (v_prod, 'purchase', 5, 'manual_entry', null);
  insert into public.inventory_movements (product_id, movement_type, quantity_delta, reference_type, reference_id)
  values (v_prod, 'service_order_usage', -1, 'service_order', v[2]) returning id into v_baixa;
  insert into public.inventory_movements (product_id, movement_type, quantity_delta, reference_type, reference_id, reverses_movement_id)
  values (v_prod, 'return', 1, 'service_order', v[2], v_baixa);
  -- modelo antigo (OS-00033): devolução sem o vínculo reverses_movement_id
  insert into public.inventory_movements (product_id, movement_type, quantity_delta, reference_type, reference_id)
  values (v_prod, 'service_order_usage', -2, 'service_order', v[1]);
  insert into public.inventory_movements (product_id, movement_type, quantity_delta, reference_type, reference_id)
  values (v_prod, 'return', 2, 'service_order', v[1]);
  v_erro := pg_temp._erro_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  insert into _resultado values ('B22 baixa estornada (com ou sem reverses_movement_id) não conta como execução: agrupa',
    v_erro is null, coalesce(v_erro, 'agrupou'));
exception when others then
  insert into _resultado values ('B22 baixa estornada (com ou sem reverses_movement_id) não conta como execução: agrupa', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C guardas ══════════════════════════════════════════════════════════════════════════════
do $$
declare
  v uuid[]; v_g uuid; v_cli uuid; e1 text; e2 text; e3 text; e4 text; e5 text; c uuid;
begin
  v := pg_temp._dupla();
  v_g := (public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null) ->> 'service_order_id')::uuid;
  select client_id into v_cli from public.service_orders where id = v[1];
  e1 := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'approved', v[1]));
  e2 := pg_temp._erro_sql(format('delete from public.service_orders where id = %L', v[1]));
  insert into _resultado values ('C1 origem OS agrupada não muda de situação nem é apagada ("Esta OS foi agrupada")',
    strpos(coalesce(e1, ''), 'Esta OS foi agrupada') > 0 and strpos(coalesce(e1, ''), 'não pode mais mudar') > 0
    and strpos(coalesce(e2, ''), 'Esta OS foi agrupada') > 0 and strpos(coalesce(e2, ''), 'histórico') > 0
    and exists (select 1 from public.service_orders where id = v[1] and status = 'cancelled'),
    'situação: ' || coalesce(e1, 'PASSOU') || ' | apagar: ' || coalesce(e2, 'PASSOU'));

  e3 := pg_temp._erro_sql(format(
    'insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status) '
    || 'values (%L, %L, %L, current_date, current_date + 7, 100, %L)', v_cli, v[1], 'Teste agrupar OS: na origem', 'pending'));
  e4 := pg_temp._erro_sql(format(
    'insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status) '
    || 'values (%L, %L, %L, current_date, current_date + 7, 100, %L)', v_cli, v_g, 'Teste agrupar OS: na agrupada', 'pending'));
  insert into _resultado values ('C2 recebível na origem OS agrupada recusado ("Esta OS foi agrupada em"); na agrupada entra',
    strpos(coalesce(e3, ''), 'Esta OS foi agrupada em') > 0 and e4 is null
    and not exists (select 1 from public.receivables where service_order_id = v[1]),
    'origem: ' || coalesce(e3, 'PASSOU') || ' | agrupada: ' || coalesce(e4, 'ok'));

  c := pg_temp._os(v_cli, (select vessel_id from public.service_orders where id = v[1]));
  e5 := pg_temp._erro_sql(format('update public.service_orders set merged_into_id = %L where id = %L', v_g, c));
  insert into _resultado values ('C3 merged_into_id de OS só pelas funções ("Só as funções Agrupar/Desagrupar OS")',
    strpos(coalesce(e5, ''), 'Só as funções Agrupar/Desagrupar OS') > 0
    and exists (select 1 from public.service_orders where id = c and merged_into_id is null),
    coalesce(e5, 'PASSOU'));
exception when others then
  insert into _resultado values ('C1–C3 guardas', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ D portas ═══════════════════════════════════════════════════════════════════════════════
do $$
declare
  v uuid[]; v_antes text; e_tec text; e_ina text; e_nul text; v_fin uuid;
begin
  v := pg_temp._dupla();
  v_antes := pg_temp._retrato(v);
  e_tec := pg_temp._erro_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('tecnico'), null);
  e_ina := pg_temp._erro_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin_inativo'), null);
  e_nul := pg_temp._erro_montar(v, null, pg_temp._numero_agrupado(), null, null);
  v_fin := (public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('financeiro'), null) ->> 'service_order_id')::uuid;
  insert into _resultado values ('D1 _montar: técnico, inativo e sem autor dão 42501; financeiro agrupa',
    e_tec like '42501 %' and e_ina like '42501 %' and e_nul like '42501 %Faça login%' and v_fin is not null,
    'técnico: ' || coalesce(e_tec, 'PASSOU') || ' | inativo: ' || coalesce(e_ina, 'PASSOU') || ' | sem autor: ' || coalesce(e_nul, 'PASSOU'));
exception when others then
  insert into _resultado values ('D1 _montar: técnico, inativo e sem autor dão 42501; financeiro agrupa', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[]; v_lv1 bigint; v_lv2 bigint; v_ic1 boolean; v_ic2 boolean; e1 text; e2 text; e3 text; v_antes text;
begin
  v := pg_temp._dupla();
  v_antes := pg_temp._retrato(v);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  select last_value, is_called into v_lv1, v_ic1 from public.document_number_seq;
  e1 := pg_temp._erro_sql(format('select public.agrupar_os(%L::uuid[])', v));
  select last_value, is_called into v_lv2, v_ic2 from public.document_number_seq;
  e2 := pg_temp._erro_sql(format('select public.desagrupar_os(%L::uuid)', v[1]));
  e3 := pg_temp._erro_sql(format('select public.os_para_agrupar(%L::uuid)', (select vessel_id from public.service_orders where id = v[1])));
  insert into _resultado values ('D2 portas públicas sem sessão e sem p_autor: "Faça login" e o document_number_seq não anda',
    auth.uid() is null and strpos(coalesce(e1, ''), 'Faça login') > 0 and strpos(coalesce(e2, ''), 'Faça login') > 0
    and strpos(coalesce(e3, ''), 'Faça login') > 0
    and v_lv1 = v_lv2 and v_ic1 = v_ic2 and pg_temp._retrato(v) = v_antes,
    'agrupar: ' || coalesce(e1, 'PASSOU') || ' | desagrupar: ' || coalesce(e2, 'PASSOU') || ' | ler: ' || coalesce(e3, 'PASSOU'));
exception when others then
  insert into _resultado values ('D2 portas públicas sem sessão e sem p_autor: "Faça login" e o document_number_seq não anda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_falhas text;
  v_f text;
begin
  v_falhas := concat_ws(', ',
    pg_temp._se(not has_function_privilege('anon', 'public.agrupar_os(uuid[], uuid, numeric, uuid)', 'execute'), 'anon agrupa'),
    pg_temp._se(not has_function_privilege('anon', 'public.desagrupar_os(uuid, uuid)', 'execute'), 'anon desagrupa'),
    pg_temp._se(not has_function_privilege('anon', 'public.os_para_agrupar(uuid, uuid, uuid, uuid[])', 'execute'), 'anon lê'),
    pg_temp._se(has_function_privilege('authenticated', 'public.agrupar_os(uuid[], uuid, numeric, uuid)', 'execute'), 'logado sem agrupar'),
    pg_temp._se(has_function_privilege('authenticated', 'public.desagrupar_os(uuid, uuid)', 'execute'), 'logado sem desagrupar'),
    pg_temp._se(has_function_privilege('authenticated', 'public.os_para_agrupar(uuid, uuid, uuid, uuid[])', 'execute'), 'logado sem ler'),
    pg_temp._se(not has_function_privilege('authenticated', 'public._agrupar_os_montar(uuid[], uuid, text, uuid, numeric)', 'execute'), 'logado executa _montar'),
    pg_temp._se(not has_function_privilege('authenticated', 'public._desagrupar_os_desfazer(uuid, uuid)', 'execute'), 'logado executa _desfazer'),
    pg_temp._se(not has_function_privilege('authenticated', 'public._os_agrupar_mover(uuid, text, text, uuid[], uuid, text)', 'execute'), 'logado executa _mover'),
    pg_temp._se(has_function_privilege('service_role', 'public._agrupar_os_montar(uuid[], uuid, text, uuid, numeric)', 'execute'), 'service_role sem _montar'),
    pg_temp._se(not has_table_privilege('anon', 'public.os_agrupamento_movidos', 'select'), 'anon lê movidos'),
    pg_temp._se(not has_table_privilege('authenticated', 'public.os_agrupamento_movidos', 'insert, update, delete'), 'logado escreve movidos'),
    pg_temp._se(exists (select 1 from pg_trigger t where t.tgrelid = 'public.service_orders'::regclass
                         and t.tgname = 'trg_os_agrupada_guarda_destino'), 'gatilho da agrupada'),
    pg_temp._se((select count(*) from pg_trigger t where t.tgrelid = 'public.service_orders'::regclass
                  and t.tgname in ('trg_orcamento_agrupado_guarda_ins', 'trg_orcamento_agrupado_guarda_upd',
                                   'trg_orcamento_agrupado_guarda_del', 'trg_orcamento_agrupado_guarda_destino')) = 4, 'gatilhos de orçamento'));
  insert into _resultado values ('D3 privilégios: anon fora, internas só service_role, movidos só leitura, gatilhos ligados',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas end);
exception when others then
  insert into _resultado values ('D3 privilégios: anon fora, internas só service_role, movidos só leitura, gatilhos ligados', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ E desagrupar ═══════════════════════════════════════════════════════════════════════════
do $$
declare
  v_a uuid := pg_temp._id('a1_a');
  v_b uuid := pg_temp._id('a1_b');
  v_novo uuid := pg_temp._id('a1_novo');
  v_token_a uuid;
  r jsonb;
  v_falhas text;
  v_pag uuid;
  v_bt uuid;
  v_lembrete2 uuid;
begin
  if v_novo is null then
    raise exception 'o A1 não deixou a agrupada (veja a linha A1)';
  end if;
  select o.share_token_antes into v_token_a from public.orcamento_agrupamento_origens o
    join public.orcamento_agrupamentos g on g.id = o.agrupamento_id
   where g.agrupado_id = v_novo and o.origem_id = v_a;

  -- Depois de agrupar, na agrupada: o Pix do saldo (recebível MOVIDO) conciliado pelo extrato e um lembrete
  -- de cobrança novo desse saldo. Os dois acompanham o recebível de volta à B.
  insert into public.payments (receivable_id, amount, payment_date, payment_method, status)
  values (pg_temp._id('a1_saldo'), 1, current_date, 'pix', 'confirmed') returning id into v_pag;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, reconciled,
                                        reconciled_payment_id, reconciled_service_order_id)
  values (current_date, 'Teste agrupar OS: Pix do saldo', 1, 'credit', true, v_pag, v_novo) returning id into v_bt;
  insert into public.whatsapp_scheduled_sends (target_kind, service_order_id, receivable_id, client_id, phone, message,
                                               scheduled_at, next_run_at, status)
  values ('receivable', v_novo, pg_temp._id('a1_saldo'), (select client_id from public.service_orders where id = v_novo),
          '550000000000', 'Teste agrupar OS: lembrete criado na agrupada', now() + interval '6 days', now() + interval '6 days', 'pending')
  returning id into v_lembrete2;

  r := public._desagrupar_os_desfazer(v_novo, pg_temp._id('admin'));

  v_falhas := concat_ws(', ',
    pg_temp._se(exists (select 1 from public.service_orders so where so.id = v_a and so.status = 'scheduled' and so.merged_into_id is null
                          and so.share_token = v_token_a and so.cancelled_at is null and so.payment_status = 'paid'
                          and so.scheduled_start_at is not null), 'A como antes'),
    pg_temp._se(exists (select 1 from public.service_orders so where so.id = v_b and so.status = 'approved' and so.merged_into_id is null
                          and so.share_token is not null and so.payment_status = 'unpaid'), 'B como antes'),
    pg_temp._se(exists (select 1 from public.service_orders so where so.id = v_novo and so.status = 'cancelled'
                          and so.share_token is null and so.cancellation_reason like 'Desagrupada%'), 'agrupada cancelada'),
    pg_temp._se(exists (select 1 from public.receivables x where x.id = pg_temp._id('a1_sinal') and x.service_order_id = v_a and x.status = 'paid')
                and exists (select 1 from public.receivables x where x.id = pg_temp._id('a1_saldo') and x.service_order_id = v_b and x.status = 'pending')
                and exists (select 1 from public.collections x where x.id = pg_temp._id('a1_cobr') and x.service_order_id = v_b)
                and exists (select 1 from public.whatsapp_scheduled_sends w where w.id = pg_temp._id('a1_lembrete') and w.service_order_id = v_b)
                and exists (select 1 from public.purchase_orders x where x.id = pg_temp._id('a1_po') and x.service_order_id = v_b)
                and exists (select 1 from public.quote_request_items i where i.id = pg_temp._id('a1_qri') and i.service_order_part_id = pg_temp._id('a1_pb'))
                and exists (select 1 from public.agenda_tasks t where t.id = pg_temp._id('a1_tarefa') and t.related_entity_id = v_a),
                'registros de volta'),
    pg_temp._se(not exists (select 1 from public.os_agrupamento_movidos m
                              join public.orcamento_agrupamentos g on g.id = m.agrupamento_id
                             where g.agrupado_id = v_novo and m.valor_antes is null
                               and m.tabela = 'receivables'
                               and exists (select 1 from public.receivables x where x.id = m.registro_id and x.service_order_id = v_novo)),
                'nada ficou na agrupada'),
    pg_temp._se(exists (select 1 from public.whatsapp_scheduled_sends w where w.id = pg_temp._id('a1_envio') and w.status = 'pending'
                          and w.last_error is null) and (r ->> 'envios_reativados')::int = 1, 'envio do link de volta'),
    pg_temp._se((select reserved_quantity from public.products where id = pg_temp._id('a1_prod')) = 5, 'reserva'),
    pg_temp._se(exists (select 1 from public.service_order_signatures g where g.id = pg_temp._id('a1_assin') and g.superseded_at is null)
                and exists (select 1 from public.service_orders so where so.id = v_a and not so.requires_resignature), 'assinatura intacta'),
    pg_temp._se(exists (select 1 from public.orcamento_agrupamentos g where g.agrupado_id = v_novo and g.desfeito_em is not null), 'agrupamento desfeito'),
    pg_temp._se(exists (select 1 from public.receivables x where x.id = pg_temp._id('a1_saldo_criado') and x.status = 'cancelled'
                          and x.service_order_id = v_novo), 'saldo lançado cancelado'),
    pg_temp._se(exists (select 1 from public.bank_transactions t where t.id = v_bt and t.reconciled_service_order_id = v_b), 'extrato segue o recebível'),
    pg_temp._se(exists (select 1 from public.whatsapp_scheduled_sends w where w.id = v_lembrete2 and w.service_order_id = v_b
                          and w.status = 'pending'), 'lembrete novo segue o recebível'),
    pg_temp._se(r -> 'origens_ids' = jsonb_build_array(v_a, v_b) and (r ->> 'registros_devolvidos')::int >= 11, 'retorno'));
  insert into _resultado values ('E1 desagrupar o A1: registros, situação, link, pagamento, reserva, envio, extrato e lembrete novo voltam; saldo lançado cancelado; assinatura intacta',
    v_falhas = '', case when v_falhas = '' then 'devolvidos=' || (r ->> 'registros_devolvidos') else 'falhou: ' || v_falhas || ' | ' || r::text end);
exception when others then
  insert into _resultado values ('E1 desagrupar o A1: registros, situação, link, pagamento, reserva, envio, extrato e lembrete novo voltam; saldo lançado cancelado; assinatura intacta', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_erro text; v uuid[]; v_g uuid; e2 text; e3 text; e4 text; v_cli uuid;
begin
  v_erro := pg_temp._erro_desfazer(pg_temp._id('a1_novo'), pg_temp._id('admin'));
  insert into _resultado values ('E2 desagrupar de novo: recusa ("já foi desagrupada")',
    strpos(coalesce(v_erro, ''), 'já foi desagrupada') > 0, coalesce(v_erro, 'PASSOU'));

  v := pg_temp._dupla();
  v_g := (public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null) ->> 'service_order_id')::uuid;
  insert into public.time_entries (service_order_id, technician_user_id, started_at, ended_at, duration_minutes)
  values (v_g, pg_temp._id('tecnico'), now() - interval '1 hour', now(), 60);
  e2 := pg_temp._erro_desfazer(v_g, pg_temp._id('admin'));
  insert into _resultado values ('E3 desagrupar depois de hora apontada: recusa ("já começou a ser executada") e nada muda',
    strpos(coalesce(e2, ''), 'já começou a ser executada (hora apontada)') > 0
    and (select count(*) from public.service_orders where id = any(v) and merged_into_id = v_g and status = 'cancelled') = 2,
    coalesce(e2, 'PASSOU'));

  v := pg_temp._dupla();
  v_g := (public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null) ->> 'service_order_id')::uuid;
  select client_id into v_cli from public.service_orders where id = v_g;
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status)
  values (v_cli, v_g, 'Teste agrupar OS: recebível novo', current_date, current_date + 7, 100, 'pending');
  e3 := pg_temp._erro_desfazer(v_g, pg_temp._id('admin'));
  insert into _resultado values ('E4 agrupada com recebível lançado depois: recusa ("conta a receber depois de agrupar")',
    strpos(coalesce(e3, ''), 'conta a receber depois de agrupar') > 0
    and exists (select 1 from public.orcamento_agrupamentos g where g.agrupado_id = v_g and g.desfeito_em is null),
    coalesce(e3, 'PASSOU'));

  v := pg_temp._dupla();
  v_g := (public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null) ->> 'service_order_id')::uuid;
  e4 := pg_temp._erro_desfazer(v_g, pg_temp._id('tecnico'));
  insert into _resultado values ('E5 técnico não desagrupa: 42501', e4 like '42501 %', coalesce(e4, 'PASSOU'));
exception when others then
  insert into _resultado values ('E2–E5 desagrupar recusas', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[]; v_g uuid; v_cli uuid; e6 text; e7 text; e8 text; v_saldo uuid;
begin
  -- Lançamento do extrato conciliado na agrupada sem ser pagamento de um recebível movido: prende
  v := pg_temp._dupla();
  v_g := (public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null) ->> 'service_order_id')::uuid;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, reconciled, reconciled_service_order_id)
  values (current_date, 'Teste agrupar OS: conciliado na agrupada', 50, 'credit', true, v_g);
  e6 := pg_temp._erro_desfazer(v_g, pg_temp._id('admin'));
  insert into _resultado values ('E6 lançamento do extrato conciliado na agrupada depois: recusa ("lançamento do extrato conciliado")',
    strpos(coalesce(e6, ''), 'lançamento do extrato conciliado depois de agrupar') > 0
    and exists (select 1 from public.orcamento_agrupamentos g where g.agrupado_id = v_g and g.desfeito_em is null),
    coalesce(e6, 'PASSOU'));

  -- Anotação do extrato na agrupada: prende
  v := pg_temp._dupla();
  v_g := (public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null) ->> 'service_order_id')::uuid;
  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, os_id, descricao)
  values ('credit', 50, current_date + 2, v_g, 'Teste agrupar OS: anotação');
  e7 := pg_temp._erro_desfazer(v_g, pg_temp._id('admin'));
  insert into _resultado values ('E7 anotação do extrato na agrupada depois: recusa ("anotação do extrato")',
    strpos(coalesce(e7, ''), 'anotação do extrato depois de agrupar') > 0, coalesce(e7, 'PASSOU'));

  -- Pagamento no saldo que o agrupar lançou: não tem original para onde voltar — recusa
  v := pg_temp._dupla();
  select client_id into v_cli from public.service_orders where id = v[1];
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, paid_amount,
                                  balance_amount, status, is_deposit)
  values (v_cli, v[1], 'Teste agrupar OS: sinal pago', current_date, current_date, 100, 100, 0, 'paid', true);
  v_g := (public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null) ->> 'service_order_id')::uuid;
  select g.saldo_criado_id into v_saldo from public.orcamento_agrupamentos g where g.agrupado_id = v_g;
  update public.receivables set paid_amount = 200, balance_amount = 300, status = 'partially_paid' where id = v_saldo;
  e8 := pg_temp._erro_desfazer(v_g, pg_temp._id('admin'));
  insert into _resultado values ('E8 pagamento no saldo lançado pelo agrupar: recusa ("já recebeu pagamento no saldo")',
    v_saldo is not null and strpos(coalesce(e8, ''), 'já recebeu pagamento no saldo') > 0
    and exists (select 1 from public.receivables x where x.id = v_saldo and x.status = 'partially_paid'),
    coalesce(e8, 'PASSOU'));
exception when others then
  insert into _resultado values ('E6–E8 desagrupar: extrato, anotação, saldo pago', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ F cancelar / reabrir a agrupada ════════════════════════════════════════════════════════
do $$
declare
  v uuid[]; v_g uuid; e1 text; e2 text; e3 text; e4 text;
begin
  v := pg_temp._dupla();
  v_g := (public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null) ->> 'service_order_id')::uuid;
  e1 := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'cancelled', v_g));
  e2 := pg_temp._erro_sql(format('select public.cancel_service_order_cascade(%L::uuid, %L)', v_g, 'teste'));
  insert into _resultado values ('F1 cancelar a agrupada (direto ou cascata) recusa "Desagrupar" e nada muda',
    strpos(coalesce(e1, ''), 'Desagrupar') > 0 and strpos(coalesce(e2, ''), 'Desagrupar') > 0
    and exists (select 1 from public.service_orders where id = v_g and status = 'approved')
    and exists (select 1 from public.orcamento_agrupamentos g where g.agrupado_id = v_g and g.desfeito_em is null),
    coalesce(e1, 'DIRETO PASSOU') || ' | ' || coalesce(e2, 'CASCATA PASSOU'));

  insert into public.time_entries (service_order_id, technician_user_id, started_at, ended_at, duration_minutes)
  values (v_g, pg_temp._id('tecnico'), now() - interval '1 hour', now(), 60);
  e3 := pg_temp._erro_sql(format('select public.cancel_service_order_cascade(%L::uuid, %L)', v_g, 'teste'));
  insert into _resultado values ('F2 agrupada que começou a execução cancela pela cascata; originais seguem histórico',
    e3 is null and exists (select 1 from public.service_orders where id = v_g and status = 'cancelled')
    and (select count(*) from public.service_orders where id = any(v) and merged_into_id = v_g and status = 'cancelled') = 2,
    coalesce(e3, 'ok'));

  v := pg_temp._dupla();
  v_g := (public._agrupar_os_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null) ->> 'service_order_id')::uuid;
  perform public._desagrupar_os_desfazer(v_g, pg_temp._id('admin'));
  e4 := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'approved', v_g));
  insert into _resultado values ('F3 agrupada já desagrupada não reabre ("Esta OS foi desagrupada")',
    e4 like '42501 %' and strpos(e4, 'Esta OS foi desagrupada') > 0
    and exists (select 1 from public.service_orders where id = v_g and status = 'cancelled')
    and (select count(*) from public.service_orders where id = any(v) and status = 'approved' and merged_into_id is null) = 2,
    coalesce(e4, 'REABRIU'));
exception when others then
  insert into _resultado values ('F1–F3 cancelar/reabrir a agrupada', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ G leitura ══════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_cli uuid; v_ves uuid; a uuid; b uuid; c uuid; v_g uuid; r jsonb; r2 jsonb; v_falhas text; v_msg text;
begin
  v_cli := pg_temp._cliente(); v_ves := pg_temp._barco(v_cli);
  a := pg_temp._os(v_cli, v_ves);
  b := pg_temp._os(v_cli, v_ves);
  c := pg_temp._os(v_cli, v_ves, 'in_progress');
  v_g := (public._agrupar_os_montar(array[a, b], null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null) ->> 'service_order_id')::uuid;
  r := public.os_para_agrupar(v_ves, null, pg_temp._id('admin'), null);
  r2 := public.orcamentos_para_agrupar(v_ves, null, pg_temp._id('admin'), null);
  v_msg := public._os_impedimento_para_agrupar(c);
  v_falhas := concat_ws(', ',
    pg_temp._se(exists (select 1 from jsonb_array_elements(r -> 'os') e where (e ->> 'id')::uuid = c
                          and not (e ->> 'elegivel')::boolean and e ->> 'motivo' = v_msg
                          and v_msg like '%já começou a ser executada%'), 'em andamento com o motivo do agrupar'),
    pg_temp._se(exists (select 1 from jsonb_array_elements(r -> 'os') e where (e ->> 'id')::uuid = v_g
                          and (e ->> 'elegivel')::boolean and jsonb_array_length(e -> 'reune') = 2), 'agrupada elegível e "reune"'),
    pg_temp._se(not exists (select 1 from jsonb_array_elements(r -> 'os') e where (e ->> 'id')::uuid in (a, b)), 'origens fora da lista'),
    pg_temp._se(jsonb_array_length(r -> 'fora_da_lista') = 2
                and (select bool_and(e ->> 'por_que' like 'já agrupada em OS-T%') from jsonb_array_elements(r -> 'fora_da_lista') e), 'fora_da_lista'),
    pg_temp._se(jsonb_array_length(r -> 'agrupados_ativos') = 1
                and (r -> 'agrupados_ativos' -> 0 ->> 'pode_desagrupar')::boolean
                and jsonb_array_length(r -> 'agrupados_ativos' -> 0 -> 'origens') = 2, 'agrupados_ativos'),
    pg_temp._se(jsonb_array_length(r2 -> 'agrupados_ativos') = 0, 'orçamento não lista agrupamento de OS'));
  insert into _resultado values ('G1 os_para_agrupar: motivo igual ao do agrupar, agrupada com "reune", fora_da_lista, agrupados_ativos; orçamentos não lista OS',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || r::text end);
exception when others then
  insert into _resultado values ('G1 os_para_agrupar: motivo igual ao do agrupar, agrupada com "reune", fora_da_lista, agrupados_ativos; orçamentos não lista OS', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
