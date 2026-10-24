-- Prova dos caminhos da conclusão, Agenda de Produção Fase 3 (pacote P3; migration 20261026100200): a conversa (o
-- rascunho de concluir e de entregar, o *grava* pela porta), as palavras *concluiu* e *entreguei* e o *desfaz* que acha a
-- OS que saiu da carteira.
-- bancada: depende de 20261026100200
--
-- Sobre a carteira da Fase 3 (scripts/bancada-agenda/fixture-fase3.sql: qui 29/10/2026, a semana de 03 a 06/11 publicada
-- pela vigia; Lenine OS-00074 sem sinal, condição 50% + 50%; Vanderlei OS-00069 com o sinal pago e o saldo na entrega):
--   R  a conversa: "terminou" vira rascunho com a releitura da saída e das cobranças, e nada muda antes do *grava*; o
--      *grava* conclui pela porta (cobranças e saída, ação concluir do dono, desfazível); em sombra concluir grava (o
--      "trabalhou" continua recusado); o lote com a conclusão recusada (período fechado) não grava nada; "entregou" numa OS
--      ainda aberta conclui e entrega; dia que não é hoje, orçamento e OS já concluída = a pergunta
--   P  as palavras: *concluiu Lenine* conclui direto e o texto diz a saída e as cobranças; de novo = "já está concluída";
--      *desfaz OS-00074* (e *desfaz Lenine*) acha a conclusão fora da carteira e volta tudo; *concluiu* sem alvo com duas OS
--      hoje = a pergunta, com uma = conclui; *entreguei Lenine* numa OS aberta conclui e entrega, numa concluída só entrega,
--      já entregue = nada; alvo que não acha = nao_achei (o turno segue ao modelo); orçamento; período fechado; quem não é
--      o administrador = 42501; o D11 (serviço que exige levantamento sem ele fechado) recusa com a frase do formulário
--   T  o texto das cobranças na voz das palavras
--   J  portas: as palavras para authenticated e service_role (anon não); as internas só service_role; quem é security
--      definer
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261026100200
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase3_caminhos.sql
--   Sem a fixture (produção) os cenários saem PULADO e só T e J rodam. Os cenários mexem em linhas só dentro de
--   subtransações desfeitas na hora; termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- O Supabase roda em UTC (o gatilho do vencimento "na entrega" usa o fuso da sessão). A bancada fica igual.
set local timezone = 'UTC';
select set_config('agenda.hoje', '2026-10-29', true);

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
declare
  v_estado text; v_msg text;
begin
  execute p_sql;
  return 'sem erro';
exception when others then
  get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  return v_estado || ' ' || v_msg;
end $f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O *grava* na hora dada (a hora do *grava* é now(); a bancada a fixa por agenda.agora, como agenda.hoje).
create function pg_temp.grava(p_autor uuid, p_dia date, p_hora text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.agora', pg_temp.em(p_dia, p_hora)::text, true);
  return public.agenda_rascunho_gravar(p_autor, p_dia);
end $f$;
create function pg_temp.modos(p_proposta text, p_vigia text) returns void language sql as $f$
  update public.agenda_config set modo_proposta = p_proposta, modo_vigia = p_vigia where id
$f$;
-- O que a conclusão mexe numa OS: status, saída, entrega, cobranças vivas e ações da agenda.
create function pg_temp.estado(p_os uuid) returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'status', so.status, 'saida', so.check_out_at, 'entrega', so.delivered_at,
    'n_rec', (select count(*) from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled'),
    'n_acoes', (select count(*) from public.agenda_acoes a where a.service_order_id = so.id))
    from public.service_orders so where so.id = p_os
$f$;

-- ── R e P: os cenários sobre a carteira da Fase 3 (só na bancada) ─────────────────────────────────────────
do $cam$
declare
  v_res     jsonb := '[]'::jsonb;
  r         jsonb;
  g         jsonb;
  v_antes   jsonb;
  v_antes2  jsonb;
  v_st      text;
  v_txt     text;
  v_acao    uuid;
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_roberto constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_lenine  constant uuid := '05000000-0000-4000-8000-000000000074';
  c_vand    constant uuid := '05000000-0000-4000-8000-000000000069';
  c_flavio  constant uuid := '05000000-0000-4000-8000-000000000104';
  d29       constant date := date '2026-10-29';
  d03       constant date := date '2026-11-03';
  d05       constant date := date '2026-11-05';
  c_cob_lenine constant text :=
    'Entrada 50% R$ 2.280,00 (vence hoje) · Saldo 50% R$ 2.280,00 (vence hoje)';
  c_fechado constant text :=
    'Não concluí: o período de outubro está fechado no financeiro (as cobranças da conclusão entrariam nele). Reabra o período e conclua de novo.';
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values ('R0 os cenários (fixture-fase3)', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.fase3');
  v_st := (select status from public.service_orders where id = c_lenine);

  -- R1/R2: a releitura não muda nada; o *grava* conclui pela porta.
  begin
    v_antes := pg_temp.estado(c_lenine);
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Lenine', 'terminou', null, null, null, 'o Lenine terminou hoje',
                                          d29, pg_temp.em(d29, '16:30'));
    v_res := pg_temp.ok(v_res, 'R1 "terminou": o rascunho de concluir com a releitura da saída e das duas cobranças; nada muda',
      (r ->> 'ok')::boolean
      and r ->> 'releitura' = E'Entendi assim, confere?\n• Concluo o Lenine (OS-00074) hoje (qui 29/10): fica registrada a saída, e saem as cobranças da condição: '
                              || c_cob_lenine || E'.\nResponda *grava* ou corrija o que estiver errado.'
      and pg_temp.estado(c_lenine) = v_antes
      and (select count(*) from public.agenda_rascunho where tipo = 'andamento' and estado = 'aberto'
                                                         and chave = format('andamento:%s:%s:concluiu', c_lenine, d29)) = 1,
      r ->> 'releitura');
    g := pg_temp.grava(c_admin, d29, '16:40');
    v_res := pg_temp.ok(v_res, 'R2 o *grava* conclui pela porta: as duas cobranças, a saída das 16:40, a ação concluir do dono (desfazível)',
      (g ->> 'ok')::boolean
      and g ->> 'texto' = E'Gravado. Agora:\n• Lenine (OS-00074): concluída — saída qui 29/10 16:40. Cobranças: ' || c_cob_lenine || '.'
      and pg_temp.estado(c_lenine) ->> 'status' = 'completed'
      and (pg_temp.estado(c_lenine) ->> 'n_rec')::int = 2
      and (select check_out_at from public.service_orders where id = c_lenine) = pg_temp.em(d29, '16:40')
      and exists (select 1 from public.agenda_acoes a where a.service_order_id = c_lenine and a.tipo = 'concluir'
                                                        and a.origem = 'dono' and a.desfazivel_ate is not null
                                                        and cardinality(a.receivable_ids) = 2),
      g ->> 'texto');
    -- R3 a OS já concluída: a conversa não deixa rascunho
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Lenine', 'concluiu', null, null, null, 'o Lenine terminou',
                                          d29, pg_temp.em(d29, '16:50'));
    v_res := pg_temp.ok(v_res, 'R3 OS já concluída: "Lenine (OS-00074) já está concluída.", nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'pergunta' = 'Lenine (OS-00074) já está concluída.' and r ->> 'motivo' = 'ja_concluida'
      and not exists (select 1 from public.agenda_rascunho where tipo = 'andamento' and estado = 'aberto'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- R4: em sombra concluir grava (vale em todos os modos); o "trabalhou" continua recusado em teste.
  begin
    perform pg_temp.modos('sombra', 'sombra');
    r := public.agenda_rascunho_andamento(c_admin, 'painel', 'Lenine', 'concluiu', null, null, null, 'o Lenine terminou',
                                          d29, pg_temp.em(d29, '16:30'));
    g := pg_temp.grava(c_admin, d29, '16:40');
    v_res := pg_temp.ok(v_res, 'R4 em sombra: concluir pela conversa grava (a conclusão pela porta vale em todos os modos)',
      (r ->> 'ok')::boolean and (g ->> 'ok')::boolean and pg_temp.estado(c_lenine) ->> 'status' = 'completed', g ->> 'texto');
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Vanderlei', 'trabalhou', null, null, null, 'o Vanderlei andou hoje',
                                          d29, pg_temp.em(d29, '16:50'));
    v_res := pg_temp.ok(v_res, 'R4 …e o "trabalhou" continua recusado em teste (Fase 2)',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'em_teste', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- R5: o lote com a conclusão recusada (outubro fechado) não grava nada, nem o "começou" do Vanderlei que vinha antes.
  begin
    v_antes := pg_temp.estado(c_lenine);
    v_antes2 := pg_temp.estado(c_vand);
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Vanderlei', 'comecou', null, null, null, 'o Vanderlei começou hoje',
                                          d29, pg_temp.em(d29, '16:30'));
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Lenine', 'concluiu', null, null, null, 'e o Lenine terminou',
                                          d29, pg_temp.em(d29, '16:31'));
    insert into public.periodos_fechados (ano, mes) values (2026, 10);
    g := pg_temp.grava(c_admin, d29, '16:40');
    v_res := pg_temp.ok(v_res, 'R5 lote com a conclusão recusada (período fechado): "Não gravei nada. Não concluí: …", nada muda',
      not (g ->> 'ok')::boolean and g ->> 'texto' = 'Não gravei nada. ' || c_fechado
      and pg_temp.estado(c_lenine) = v_antes and pg_temp.estado(c_vand) = v_antes2
      and (select count(*) from public.agenda_rascunho where tipo = 'andamento' and estado = 'aberto') = 2,
      g ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- R6: "entregou" numa OS ainda aberta: a releitura diz que conclui junto; o *grava* conclui e entrega.
  begin
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Lenine', 'entregue', null, null, null, 'o barco do Lenine foi entregue',
                                          d29, pg_temp.em(d29, '16:30'));
    v_res := pg_temp.ok(v_res, 'R6 "entregue" numa OS aberta: a releitura avisa que conclui junto (a saída e as cobranças)',
      (r ->> 'ok')::boolean
      and r ->> 'releitura' = format(E'Entendi assim, confere?\n• Marco a entrega do Lenine (OS-00074) hoje (qui 29/10): ainda está %s, então concluo junto: fica registrada a saída, e saem as cobranças da condição: %s.\nResponda *grava* ou corrija o que estiver errado.',
                                     public._agenda_status_texto(v_st), c_cob_lenine),
      r ->> 'releitura');
    g := pg_temp.grava(c_admin, d29, '16:40');
    v_res := pg_temp.ok(v_res, 'R6 …o *grava* conclui e entrega (duas ações: concluir e entregar)',
      (g ->> 'ok')::boolean
      and g ->> 'texto' like E'Gravado. Agora:\n• O Lenine (OS-00074) ainda estava % concluí e marquei a entrega (qui 29/10 às 16:40). Cobranças: %'
      and pg_temp.estado(c_lenine) ->> 'status' = 'completed'
      and (select delivered_at from public.service_orders where id = c_lenine) = pg_temp.em(d29, '16:40')
      and (select count(*) from public.agenda_acoes a where a.service_order_id = c_lenine and a.tipo in ('concluir', 'entregar')) = 2,
      g ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- R7: o dia que não é hoje, o orçamento e o sem trecho: a pergunta, nada no rascunho.
  begin
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Lenine', 'concluiu', 'ontem', null, null, 'o Lenine terminou ontem',
                                          d29, pg_temp.em(d29, '16:30'));
    g := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Robson', 'concluiu', null, null, null, 'o Robson terminou',
                                          d29, pg_temp.em(d29, '16:30'));
    v_res := pg_temp.ok(v_res, 'R7 "terminou ontem": a conclusão fica com a data de hoje; o orçamento (ORÇ-00083) não conclui; nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'so_hoje'
      and r ->> 'pergunta' = 'A conclusão fica com a data de hoje (é nela que entram a saída e as cobranças): me diga sem o dia.'
      and not (g ->> 'ok')::boolean and g ->> 'motivo' = 'orcamento'
      and g ->> 'pergunta' = 'Robson (ORÇ-00083) ainda é orçamento: converta em OS antes de concluir.'
      and not exists (select 1 from public.agenda_rascunho where tipo = 'andamento' and estado = 'aberto'),
      r ->> 'pergunta' || ' / ' || (g ->> 'pergunta'));
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Lenine', 'concluiu', null, null, null, '   ', d29, pg_temp.em(d29, '16:30'));
    v_res := pg_temp.ok(v_res, 'R7 …sem o trecho do dono: pede as palavras dele', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'sem_trecho', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- P1–P3: *concluiu Lenine* direto; de novo; *desfaz* pelo número e pelo nome.
  begin
    r := public.agenda_concluir_dito(c_admin, 'Lenine', 'whatsapp', d29, pg_temp.em(d29, '16:30'));
    v_res := pg_temp.ok(v_res, 'P1 *concluiu Lenine*: conclui direto, as duas cobranças e a saída; o texto diz como desfazer',
      (r ->> 'ok')::boolean and (r ->> 'mudou')::boolean and r ->> 'status' = 'ok'
      and r ->> 'texto' = 'Concluí o Lenine (OS-00074) hoje (qui 29/10, 16:30). Saíram as cobranças da condição: ' || c_cob_lenine
                          || '. *desfaz OS-00074* volta como estava.'
      and pg_temp.estado(c_lenine) ->> 'status' = 'completed' and (pg_temp.estado(c_lenine) ->> 'n_rec')::int = 2,
      r ->> 'texto');
    r := public.agenda_concluir_dito(c_admin, 'Lenine', 'whatsapp', d29, pg_temp.em(d29, '16:35'));
    v_res := pg_temp.ok(v_res, 'P1 …de novo: "Lenine (OS-00074) já está concluída.", nada nasce',
      (r ->> 'ok')::boolean and not (r ->> 'mudou')::boolean and r ->> 'status' = 'ja_concluida'
      and r ->> 'texto' = 'Lenine (OS-00074) já está concluída.' and (pg_temp.estado(c_lenine) ->> 'n_rec')::int = 2, r::text);
    v_acao := (select a.id from public.agenda_acoes a where a.service_order_id = c_lenine and a.tipo = 'concluir');
    v_res := pg_temp.ok(v_res, 'P2 a OS concluída saiu da carteira, mas *desfaz OS-00074* e *desfaz Lenine* acham a conclusão',
      public.agenda_acao_desfazivel('OS-00074', d29, pg_temp.em(d29, '16:40')) ->> 'acao_id' = v_acao::text
      and public.agenda_acao_desfazivel('Lenine', d29, pg_temp.em(d29, '16:40')) ->> 'acao_id' = v_acao::text,
      public.agenda_acao_desfazivel('OS-00074', d29, pg_temp.em(d29, '16:40'))::text);
    r := public.agenda_desfazer_dito(c_admin, 'OS-00074', 'whatsapp', d29, pg_temp.em(d29, '16:40'));
    v_res := pg_temp.ok(v_res, 'P3 *desfaz OS-00074*: volta o status de antes, sem a saída e com as duas cobranças canceladas',
      (r ->> 'ok')::boolean and pg_temp.estado(c_lenine) ->> 'status' = v_st
      and pg_temp.estado(c_lenine) ->> 'saida' is null and (pg_temp.estado(c_lenine) ->> 'n_rec')::int = 0
      and r ->> 'texto' like 'Desfeito: o Lenine (OS-00074) voltou para %', r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- P2b: sem mudança desfazível, o *desfaz* de uma OS fora da carteira responde como antes (pode ser de outra ferramenta):
  -- a OS-00032 concluída por fora da agenda (o UPDATE de antes da porta) não tem ação da agenda.
  begin
    update public.service_orders set status = 'completed', check_out_at = pg_temp.em(d29, '10:00')
     where id = '05000000-0000-4000-8000-000000000032';
    r := public.agenda_acao_desfazivel('OS-00032', d29, pg_temp.em(d29, '16:40'));
    v_res := pg_temp.ok(v_res, 'P2b OS fora da carteira sem mudança da agenda: o *desfaz* continua fora_da_carteira',
      r ->> 'status' = 'fora_da_carteira' and r ->> 'acao_id' is null, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- P4: *concluiu* sem alvo — duas OS no plano de hoje = a pergunta; uma = conclui.
  begin
    v_antes := pg_temp.estado(c_vand);
    v_antes2 := pg_temp.estado(c_flavio);
    r := public.agenda_concluir_dito(c_admin, null, 'whatsapp', d03, pg_temp.em(d03, '17:00'));
    v_res := pg_temp.ok(v_res, 'P4 *concluiu* sem alvo com duas OS no plano de ter 03/11: a pergunta, nada muda',
      not (r ->> 'ok')::boolean and r ->> 'status' = 'ambiguo'
      and r ->> 'texto' = 'Qual? Vanderlei (OS-00069) ou Flávio (OS-00104)? Diga *concluiu Vanderlei*.'
      and pg_temp.estado(c_vand) = v_antes and pg_temp.estado(c_flavio) = v_antes2, r ->> 'texto');
    r := public.agenda_concluir_dito(c_admin, null, 'whatsapp', d05, pg_temp.em(d05, '17:00'));
    v_res := pg_temp.ok(v_res, 'P4 …com uma só (qui 05/11, o Vanderlei): conclui; o sinal pago já era a cobrança e o saldo passa a vencer hoje',
      (r ->> 'ok')::boolean and (r ->> 'mudou')::boolean
      and r ->> 'texto' = 'Concluí o Vanderlei (OS-00069) hoje (qui 05/11, 17:00). As cobranças já existiam (sinal pago); o saldo na entrega (R$ 2.800,00) passa a vencer hoje. *desfaz OS-00069* volta como estava.'
      and pg_temp.estado(c_vand) ->> 'status' = 'completed', r ->> 'texto');
    r := public.agenda_concluir_dito(c_admin, null, 'whatsapp', date '2026-11-02', pg_temp.em(date '2026-11-02', '17:00'));
    v_res := pg_temp.ok(v_res, 'P4 …sem nenhuma no plano (seg 02/11, Finados): pede o nome',
      not (r ->> 'ok')::boolean and r ->> 'status' = 'nenhuma'
      and r ->> 'texto' = 'Hoje não tem serviço no plano para concluir. Diga *concluiu* e o nome do cliente.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- P5: *entreguei Lenine* numa OS ainda aberta conclui e entrega.
  begin
    r := public.agenda_entregar_dito(c_admin, 'Lenine', 'whatsapp', d29, pg_temp.em(d29, '16:30'));
    v_res := pg_temp.ok(v_res, 'P5 *entreguei Lenine* numa OS aberta: conclui e entrega na mesma ordem, e o texto diz as duas coisas',
      (r ->> 'ok')::boolean and (r ->> 'concluiu')::boolean
      and r ->> 'texto' = format('Lenine (OS-00074): ainda estava %s; concluí e marquei a entrega (qui 29/10 às 16:30). Saíram as cobranças da condição: %s. *desfaz OS-00074* volta como estava.',
                                 public._agenda_status_texto(v_st), c_cob_lenine)
      and pg_temp.estado(c_lenine) ->> 'status' = 'completed'
      and (select delivered_at from public.service_orders where id = c_lenine) = pg_temp.em(d29, '16:30'), r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- P6: *entreguei Lenine* numa OS concluída (fora da carteira, pelo nome) só entrega; de novo = já entregue; *desfaz*.
  begin
    r := public.agenda_concluir_dito(c_admin, 'Lenine', 'whatsapp', d29, pg_temp.em(d29, '16:30'));
    r := public.agenda_entregar_dito(c_admin, 'Lenine', 'whatsapp', d29, pg_temp.em(d29, '17:10'));
    v_res := pg_temp.ok(v_res, 'P6 *entreguei Lenine* com a OS já concluída: acha pelo nome fora da carteira e só entrega',
      (r ->> 'ok')::boolean and not (r ->> 'concluiu')::boolean
      and r ->> 'texto' = 'Entregue: o Lenine (OS-00074), qui 29/10 às 17:10.'
      and (select delivered_at from public.service_orders where id = c_lenine) = pg_temp.em(d29, '17:10'), r ->> 'texto');
    r := public.agenda_entregar_dito(c_admin, 'Lenine', 'whatsapp', d29, pg_temp.em(d29, '17:20'));
    v_res := pg_temp.ok(v_res, 'P6 …de novo: "O Lenine (OS-00074) já foi entregue em qui 29/10.", nada muda',
      (r ->> 'ok')::boolean and not (r ->> 'mudou')::boolean and r ->> 'status' = 'ja_entregue'
      and r ->> 'texto' = 'O Lenine (OS-00074) já foi entregue em qui 29/10.', r::text);
    r := public.agenda_desfazer_dito(c_admin, 'OS-00074', 'whatsapp', d29, pg_temp.em(d29, '17:30'));
    v_res := pg_temp.ok(v_res, 'P6 …*desfaz OS-00074* tira a entrega (a última mudança) e a conclusão fica',
      (r ->> 'ok')::boolean and (select delivered_at from public.service_orders where id = c_lenine) is null
      and pg_temp.estado(c_lenine) ->> 'status' = 'completed', r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- P7: alvo que o banco não acha (o turno segue ao modelo), orçamento, período fechado, quem não é o administrador.
  begin
    v_antes := pg_temp.estado(c_lenine);
    r := public.agenda_concluir_dito(c_admin, 'pagamento', 'whatsapp', d29, pg_temp.em(d29, '16:30'));
    g := public.agenda_entregar_dito(c_admin, 'instalação', 'whatsapp', d29, pg_temp.em(d29, '16:30'));
    v_res := pg_temp.ok(v_res, 'P7 alvo que não é OS ("concluiu pagamento", "entreguei instalação"): nao_achei, nada muda',
      not (r ->> 'ok')::boolean and r ->> 'status' = 'nao_achei' and not (g ->> 'ok')::boolean and g ->> 'status' = 'nao_achei'
      and pg_temp.estado(c_lenine) = v_antes, r::text || ' / ' || g::text);
    r := public.agenda_concluir_dito(c_admin, 'Robson', 'whatsapp', d29, pg_temp.em(d29, '16:30'));
    v_res := pg_temp.ok(v_res, 'P7 *concluiu Robson* (ORÇ-00083, orçamento aprovado): não conclui, pede a conversão',
      not (r ->> 'ok')::boolean and r ->> 'status' = 'orcamento'
      and r ->> 'texto' = 'Robson (ORÇ-00083) ainda é orçamento: converta em OS antes de concluir.'
      and (select status from public.service_orders where id = '05000000-0000-4000-8000-000000000083') = 'draft', r::text);
    insert into public.periodos_fechados (ano, mes) values (2026, 10);
    r := public.agenda_concluir_dito(c_admin, 'Lenine', 'whatsapp', d29, pg_temp.em(d29, '16:30'));
    v_res := pg_temp.ok(v_res, 'P7 *concluiu Lenine* com outubro fechado: o texto da porta, nada muda',
      not (r ->> 'ok')::boolean and r ->> 'status' = 'recusada' and r ->> 'texto' = c_fechado
      and pg_temp.estado(c_lenine) = v_antes, r ->> 'texto');
    delete from public.periodos_fechados where ano = 2026 and mes = 10;
    v_txt := pg_temp.erro_de(format($s$select public.agenda_concluir_dito(%L, 'Lenine', 'whatsapp', date '2026-10-29',
                                     timestamptz '2026-10-29 16:30-03')$s$, c_roberto))
             || ' | ' || pg_temp.erro_de(format($s$select public.agenda_entregar_dito(%L, 'Lenine', 'whatsapp', date '2026-10-29',
                                     timestamptz '2026-10-29 16:30-03')$s$, c_roberto));
    v_res := pg_temp.ok(v_res, 'P7 quem não é o administrador: 42501 nas duas palavras, nada muda',
      v_txt = '42501 Só o administrador mexe na agenda. | 42501 Só o administrador mexe na agenda.'
      and pg_temp.estado(c_lenine) = v_antes, v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- P8: o D11 — o serviço que exige levantamento sem levantamento fechado não deixa concluir (conversa e palavras); com o
  -- levantamento fechado, conclui.
  begin
    v_antes := pg_temp.estado(c_lenine);
    update public.services set requires_survey = true where id = '5e000000-0000-4000-8000-000000000003';
    insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                               unit_price_snapshot, line_total, created_at)
    values ('d3300000-0000-4000-8000-000000000001', c_lenine, '5e000000-0000-4000-8000-000000000003',
            'Revisão do sistema elétrico', 'unit', 1, 0, 0, timestamptz '2026-10-20 12:00-03');
    r := public.agenda_concluir_dito(c_admin, 'Lenine', 'whatsapp', d29, pg_temp.em(d29, '16:30'));
    g := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Lenine', 'terminou', null, null, null, 'o Lenine terminou',
                                          d29, pg_temp.em(d29, '16:30'));
    v_txt := 'Para concluir, responda o levantamento de: Revisão do sistema elétrico. Esses serviços estão marcados como "exige levantamento".';
    v_res := pg_temp.ok(v_res, 'P8 D11: serviço que exige levantamento sem ele fechado = a frase do formulário (palavra e conversa), nada muda',
      not (r ->> 'ok')::boolean and r ->> 'status' = 'levantamento' and r ->> 'texto' = v_txt
      and not (g ->> 'ok')::boolean and g ->> 'motivo' = 'levantamento' and g ->> 'pergunta' = v_txt
      and (public.agenda_entregar_dito(c_admin, 'Lenine', 'whatsapp', d29, pg_temp.em(d29, '16:30')) ->> 'status') = 'levantamento'
      and pg_temp.estado(c_lenine) = v_antes, r ->> 'texto');
    insert into public.service_surveys (service_order_id, service_id, trigger_reason, status)
    values (c_lenine, '5e000000-0000-4000-8000-000000000003', 'TESTE P3', 'closed');
    r := public.agenda_concluir_dito(c_admin, 'Lenine', 'whatsapp', d29, pg_temp.em(d29, '16:40'));
    v_res := pg_temp.ok(v_res, 'P8 …com o levantamento fechado, conclui',
      (r ->> 'ok')::boolean and (r ->> 'mudou')::boolean and pg_temp.estado(c_lenine) ->> 'status' = 'completed', r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end $cam$;

-- ── T. O texto das cobranças na voz das palavras (roda sempre) ────────────────────────────────────────────
insert into _resultado
select 'T1 "Cobrança(s): …" vira "Saiu/Saíram a(s) cobrança(s) da condição: …"; o resto fica',
       public._agenda_cobrancas_da_palavra('Cobrança: Saldo R$ 10,00 (vence hoje).') = 'Saiu a cobrança da condição: Saldo R$ 10,00 (vence hoje).'
       and public._agenda_cobrancas_da_palavra('Cobranças: A R$ 1,00 (vence hoje) · B R$ 2,00 (vence hoje).')
           = 'Saíram as cobranças da condição: A R$ 1,00 (vence hoje) · B R$ 2,00 (vence hoje).'
       and public._agenda_cobrancas_da_palavra('As cobranças já existiam.') = 'As cobranças já existiam.'
       and public._agenda_cobrancas_da_palavra(null) = '',
       null;

-- ── J. Portas (rodam sempre) ────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('J1 %s: authenticated e service_role executam; anon não', f),
       has_function_privilege('authenticated', f::regprocedure, 'execute')
       and has_function_privilege('service_role', f::regprocedure, 'execute')
       and not has_function_privilege('anon', f::regprocedure, 'execute'), null
  from unnest(array[
    'public.agenda_concluir_dito(uuid, text, text, date, timestamptz)',
    'public.agenda_entregar_dito(uuid, text, text, date, timestamptz)',
    'public.agenda_rascunho_andamento(uuid, text, text, text, text, text[], text, text, date, timestamptz)',
    'public.agenda_rascunho_gravar(uuid, date)',
    'public.agenda_acao_desfazivel(text, date, timestamptz)']) f;

insert into _resultado
select format('J2 %s: só service_role', f),
       not has_function_privilege('authenticated', f::regprocedure, 'execute')
       and not has_function_privilege('anon', f::regprocedure, 'execute')
       and has_function_privilege('service_role', f::regprocedure, 'execute'), null
  from unnest(array[
    'public._agenda_rascunho_marco(uuid, text, text, text, text, text, date)',
    'public._agenda_os_da_entrega(text, date)',
    'public._agenda_cobrancas_da_releitura(uuid, date)',
    'public._agenda_cobrancas_da_palavra(text)',
    'public._agenda_aplicar_pedido(uuid, text, uuid, jsonb, text, text, date, timestamptz)']) f;

insert into _resultado
select 'J3 as palavras, o andamento e o *grava* são security definer; a releitura, a OS da entrega, os textos, o pedido e o desfazível não; todas com search_path fixo',
       bool_and(p.prosecdef = (p.proname in ('agenda_concluir_dito', 'agenda_entregar_dito', 'agenda_rascunho_andamento',
                                             'agenda_rascunho_gravar')))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and count(*) = 10,
       string_agg(p.proname || case when p.prosecdef then ' (definer)' else '' end, ', ' order by p.proname)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('agenda_concluir_dito', 'agenda_entregar_dito', 'agenda_rascunho_andamento', 'agenda_rascunho_gravar',
                     '_agenda_rascunho_marco', '_agenda_os_da_entrega', '_agenda_cobrancas_da_releitura',
                     '_agenda_cobrancas_da_palavra', '_agenda_aplicar_pedido', 'agenda_acao_desfazivel');

select teste, ok, detalhe from _resultado order by teste;

rollback;
