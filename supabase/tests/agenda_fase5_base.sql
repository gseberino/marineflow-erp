-- Prova da base da Agenda de Produção, Fase 5 (pacote P1): o modo e os parâmetros da mensagem ao cliente, o que foi dito
-- ao cliente (prometido_*), as 2 tabelas do cliente e as listas fechadas ampliadas (migrations 20261028100000 e
-- 20261028100100; o parâmetro da correção C1, cliente_pedido_max_du, de 20261028100700).
-- bancada: depende de 20261028100700
--
--   B1 colunas, DEFAULTs e CHECKs (agenda_config, os_planejamento, agenda_cliente_mensagens, agenda_cliente_respostas, as
--      listas fechadas ampliadas); todo CHECK novo de agenda_config tem caso; o modelo gerado (M1–M10)
--   B2 RLS e privilégios (anon nada; o técnico não lê e não grava o prometido; as internas sem grant; definer só elas)
--   B3 a coluna gerada critica com cliente_aviso (as 6 críticas de antes iguais; cliente_aprovar e cliente_resposta não)
--   B4 as tabelas não se apagam e só mudam as colunas de estado (a hora só enquanto a mensagem espera)
--   B5 o espelho scheduled_* da Fase 2 continua o mesmo (publicar → mín/máx; desfazer → volta) e a Fase 5 não o escreve:
--      o contexto lê o plano, não o espelho
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase5_base.sql
--   Seguro em produção: as linhas de teste ("TESTE AG5") só são inseridas; termina em ROLLBACK. B5 roda só na bancada (a
--   fixture-fase5; fora dela, PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Executa um comando e diz que porta o recusou: o nome do CHECK, do índice único ou da FK; 'aceitou' quando entrou (e
-- desfaz); 'erro <estado>: <mensagem>' para o resto.
create function pg_temp.recusa(p_sql text) returns text language plpgsql as $f$
declare
  v_nome text; v_estado text; v_msg text;
begin
  begin
    execute p_sql;
    raise exception using errcode = 'P0001', message = '__aceitou__';
  exception when others then
    get stacked diagnostics v_nome = constraint_name, v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg = '__aceitou__' then return 'aceitou'; end if;
    if v_estado in ('23514', '23505', '23503', '23502', '23P01') then return coalesce(nullif(v_nome, ''), v_estado); end if;
    return 'erro ' || v_estado || ': ' || v_msg;
  end;
end $f$;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou 'erro <estado>: <mensagem>'.
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- O INSERT de uma linha de p_tabela com as colunas de p_linha (jsonb): só as chaves dadas entram (as outras ficam com o
-- DEFAULT; a coluna gerada nunca).
create function pg_temp.ins(p_tabela text, p_linha jsonb) returns text language sql immutable as $f$
  select format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, %L::jsonb)',
                p_tabela, string_agg(format('%I', k), ', '), string_agg(format('%I', k), ', '), p_tabela, p_linha::text)
    from jsonb_object_keys(p_linha) k
$f$;

-- As linhas de teste: um cliente, o bem e a OS dele (não dependem da fixture: a prova roda também em produção).
insert into public.clients (id, type, name) values ('d5000000-0000-4000-8000-0000000000e1', 'individual', 'TESTE AG5 Cliente');
insert into public.vessels (id, client_id, name, asset_type)
values ('d5000000-0000-4000-8000-0000000000e2', 'd5000000-0000-4000-8000-0000000000e1', 'TESTE AG5 Barco', 'Lancha');
insert into public.service_orders (id, service_order_number, client_id, vessel_id, status)
values ('d5000000-0000-4000-8000-0000000000e3', 'OS-TESTE-AG5', 'd5000000-0000-4000-8000-0000000000e1',
        'd5000000-0000-4000-8000-0000000000e2', 'open');
insert into public.os_planejamento (service_order_id) values ('d5000000-0000-4000-8000-0000000000e3');

create temp table _base (nome text primary key, linha jsonb) on commit drop;
insert into _base values
  ('msg', jsonb_build_object('client_id', 'd5000000-0000-4000-8000-0000000000e1',
                             'service_order_id', 'd5000000-0000-4000-8000-0000000000e3',
                             'tipo', 'confirmar', 'origem', 'rodada', 'modo', 'sombra',
                             'texto', 'Teste, conseguimos encaixar o serviço na sua lancha para terça (03/11), à tarde.',
                             'enviar_em', '2026-10-31 09:00-03', 'valida_ate', '2026-10-31 13:00-03', 'aprovacao', 'livre',
                             'dedupe_key', 'agenda-cliente:teste:caso')),
  ('resp', jsonb_build_object('client_id', 'd5000000-0000-4000-8000-0000000000e1', 'recebida_em', '2026-10-31 09:30-03',
                              'tipo_msg', 'text', 'texto', 'sim', 'intencao', 'confirma', 'efeito', 'confirmou',
                              'modo', 'sombra'));
create function pg_temp.msg(p_over jsonb) returns text language sql stable as $f$
  select pg_temp.ins('agenda_cliente_mensagens', (select linha from _base where nome = 'msg') || p_over)
$f$;
create function pg_temp.resp(p_over jsonb) returns text language sql stable as $f$
  select pg_temp.ins('agenda_cliente_respostas', (select linha from _base where nome = 'resp') || p_over)
$f$;

-- A mensagem e a resposta de teste que os casos de "a mesma chave"/"o mesmo whatsapp" e o B4 mexem.
do $$ begin
  execute pg_temp.msg('{"id": "d5000000-0000-4000-8000-0000000000c1", "dedupe_key": "agenda-cliente:teste:1:sombra"}');
  execute pg_temp.resp('{"id": "d5000000-0000-4000-8000-0000000000c2", "whatsapp_message_id": "d5000000-0000-4000-8000-0000000000c3"}');
end $$;

-- ── B1. Colunas, DEFAULTs e CHECKs ──────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B1a agenda_config: modo_cliente nasce desligado na linha e o DEFAULT da coluna é sombra; a lista de tipos vazia; os 24 parâmetros com o valor da spec (e o cliente_pedido_max_du da correção C1)',
       c.modo_cliente = 'desligado' and c.cliente_tipos_ligados = '{}'
       and (select pg_get_expr(d.adbin, d.adrelid) from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'modo_cliente') like '''sombra''%'
       and c.cliente_janela_inicio = time '08:00' and c.cliente_janela_fim = time '19:00' and c.cliente_sabado_fim = time '13:00'
       and c.cliente_dia_max = 1 and c.cliente_semana_max = 3 and c.cliente_total_dia_max = 8
       and c.cliente_intervalo_min_s = 30 and c.cliente_intervalo_max_s = 60 and c.cliente_aprovacao_dias = 3
       and c.cliente_hora_toque = time '09:00' and c.cliente_hora_preparo = time '17:00' and c.cliente_confirmar_du = 3
       and c.cliente_resposta_validade = interval '72 hours' and c.cliente_sem_resposta_horas = 48
       and c.cliente_atraso_na_hora_du = 2 and c.cliente_acesso_validade_dias = 90 and c.cliente_andamento_min_du = 5
       and c.cliente_andamento_intervalo_dias = 6 and c.cliente_pronto_lembrete_dias = 3 and c.cliente_pos_dias = 5
       and c.cliente_conversa_dias = 365 and c.cliente_conversa_viva_min = 60 and c.cliente_mesmo_tipo_horas = 24
       -- (correção C1) o teto do dia que o cliente pede: 10 dias úteis do combinado
       and c.cliente_pedido_max_du = 10
       -- os da Fase 2 reusados (não duplicados)
       and c.atraso_longo_dias = 7 and c.remarcar_confirmado_du = 2
       and not exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass
                         and a.attname in ('cliente_atraso_longo_dias', 'cliente_remarcar_confirmado_du') and not a.attisdropped),
       to_jsonb(c)::text
  from public.agenda_config c;

insert into _resultado
select 'B1b os_planejamento: as 9 colunas novas, todas nulas, com o tipo da spec',
       count(*) = 9
       and bool_and(not a.attnotnull and a.atthasdef = false)
       and string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
           = 'acesso_ok_em:timestamp with time zone,prometido_ate:date,prometido_de:date,prometido_em:timestamp with time zone,'
             || 'prometido_fonte:text,prometido_mensagem_id:uuid,prometido_original_ate:date,prometido_tipo:text,servico_cliente:text',
       string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
  from pg_attribute a
 where a.attrelid = 'public.os_planejamento'::regclass and not a.attisdropped
   and a.attname in ('prometido_tipo', 'prometido_de', 'prometido_ate', 'prometido_original_ate', 'prometido_em',
                     'prometido_fonte', 'prometido_mensagem_id', 'servico_cliente', 'acesso_ok_em');

create temp table _casos (grupo text, nome text, sql text, espera text) on commit drop;
insert into _casos values
  -- agenda_config
  ('config', 'modo_cliente', $q$update public.agenda_config set modo_cliente = 'x'$q$, 'agenda_config_modo_cliente_check'),
  ('config', 'tipo que não existe na lista', $q$update public.agenda_config set cliente_tipos_ligados = '{confirmar,cobranca}'$q$, 'agenda_config_cliente_tipos_ligados_check'),
  ('config', 'janela começa 06:59', $q$update public.agenda_config set cliente_janela_inicio = '06:59'$q$, 'agenda_config_cliente_janela_inicio_check'),
  ('config', 'janela termina 20:01', $q$update public.agenda_config set cliente_janela_fim = '20:01'$q$, 'agenda_config_cliente_janela_fim_check'),
  ('config', 'sábado termina 14:01', $q$update public.agenda_config set cliente_sabado_fim = '14:01'$q$, 'agenda_config_cliente_sabado_fim_check'),
  ('config', 'sábado termina 10:59', $q$update public.agenda_config set cliente_sabado_fim = '10:59'$q$, 'agenda_config_cliente_sabado_fim_check'),
  ('config', 'cliente_dia_max 3', $q$update public.agenda_config set cliente_dia_max = 3$q$, 'agenda_config_cliente_dia_max_check'),
  ('config', 'cliente_semana_max 0', $q$update public.agenda_config set cliente_semana_max = 0$q$, 'agenda_config_cliente_semana_max_check'),
  ('config', 'cliente_total_dia_max 31', $q$update public.agenda_config set cliente_total_dia_max = 31$q$, 'agenda_config_cliente_total_dia_max_check'),
  ('config', 'intervalo mínimo 9 s', $q$update public.agenda_config set cliente_intervalo_min_s = 9$q$, 'agenda_config_cliente_intervalo_min_s_check'),
  ('config', 'intervalo mínimo acima do máximo', $q$update public.agenda_config set cliente_intervalo_min_s = 61$q$, 'agenda_config_cliente_intervalo_min_s_check'),
  ('config', 'intervalo máximo 301 s', $q$update public.agenda_config set cliente_intervalo_max_s = 301$q$, 'agenda_config_cliente_intervalo_max_s_check'),
  ('config', 'aprovação 11 dias', $q$update public.agenda_config set cliente_aprovacao_dias = 11$q$, 'agenda_config_cliente_aprovacao_dias_check'),
  ('config', 'toque antes da janela (07:59)', $q$update public.agenda_config set cliente_hora_toque = '07:59'$q$, 'agenda_config_cliente_hora_toque_check'),
  ('config', 'toque no fim da janela (19:00)', $q$update public.agenda_config set cliente_hora_toque = '19:00'$q$, 'agenda_config_cliente_hora_toque_check'),
  ('config', 'preparo depois da janela (19:30)', $q$update public.agenda_config set cliente_hora_preparo = '19:30'$q$, 'agenda_config_cliente_hora_preparo_check'),
  ('config', 'D-6', $q$update public.agenda_config set cliente_confirmar_du = 6$q$, 'agenda_config_cliente_confirmar_du_check'),
  ('config', 'validade da resposta 23 h', $q$update public.agenda_config set cliente_resposta_validade = '23 hours'$q$, 'agenda_config_cliente_resposta_validade_check'),
  ('config', 'validade da resposta 8 dias', $q$update public.agenda_config set cliente_resposta_validade = '8 days'$q$, 'agenda_config_cliente_resposta_validade_check'),
  ('config', 'sem resposta 97 h', $q$update public.agenda_config set cliente_sem_resposta_horas = 97$q$, 'agenda_config_cliente_sem_resposta_horas_check'),
  ('config', 'atraso na hora 0 du', $q$update public.agenda_config set cliente_atraso_na_hora_du = 0$q$, 'agenda_config_cliente_atraso_na_hora_du_check'),
  ('config', 'acesso vale 6 dias', $q$update public.agenda_config set cliente_acesso_validade_dias = 6$q$, 'agenda_config_cliente_acesso_validade_dias_check'),
  ('config', 'andamento a partir de 21 du', $q$update public.agenda_config set cliente_andamento_min_du = 21$q$, 'agenda_config_cliente_andamento_min_du_check'),
  ('config', 'andamento a cada 2 dias', $q$update public.agenda_config set cliente_andamento_intervalo_dias = 2$q$, 'agenda_config_cliente_andamento_intervalo_dias_check'),
  ('config', 'lembrete do pronto em 8 dias', $q$update public.agenda_config set cliente_pronto_lembrete_dias = 8$q$, 'agenda_config_cliente_pronto_lembrete_dias_check'),
  ('config', 'pós-serviço em 2 dias', $q$update public.agenda_config set cliente_pos_dias = 2$q$, 'agenda_config_cliente_pos_dias_check'),
  ('config', 'conversa em 731 dias', $q$update public.agenda_config set cliente_conversa_dias = 731$q$, 'agenda_config_cliente_conversa_dias_check'),
  ('config', 'conversa viva 241 min', $q$update public.agenda_config set cliente_conversa_viva_min = 241$q$, 'agenda_config_cliente_conversa_viva_min_check'),
  ('config', 'pedido do cliente a 31 dias úteis (correção C1)', $q$update public.agenda_config set cliente_pedido_max_du = 31$q$, 'agenda_config_cliente_pedido_max_du_check'),
  ('config', 'pedido do cliente a 0 dia útil (correção C1)', $q$update public.agenda_config set cliente_pedido_max_du = 0$q$, 'agenda_config_cliente_pedido_max_du_check'),
  ('config', 'mesmo tipo em 11 h', $q$update public.agenda_config set cliente_mesmo_tipo_horas = 11$q$, 'agenda_config_cliente_mesmo_tipo_horas_check'),
  ('config', 'os limites que entram (ligado, as 4 ondas, 07:00, 20:00, sáb 14:00, 10–300 s, 0 dias de aprovação e de conversa)',
   $q$update public.agenda_config set modo_cliente = 'ligado',
        cliente_tipos_ligados = '{material_chegou,nova_data,pode_atrasar,confirmar,vespera,acesso,mudanca_no_dia,pronto,pronto_lembrete,andamento,pos_servico}',
        cliente_janela_inicio = '07:00', cliente_janela_fim = '20:00', cliente_sabado_fim = '14:00', cliente_intervalo_min_s = 10,
        cliente_intervalo_max_s = 300, cliente_aprovacao_dias = 0, cliente_conversa_dias = 0, cliente_hora_toque = '07:00',
        cliente_hora_preparo = '19:59'$q$, 'aceitou'),
  -- os_planejamento (a OS de teste)
  ('planejamento', 'tipo do prometido fora da lista', $q$update public.os_planejamento set prometido_tipo = 'talvez', prometido_ate = '2026-11-05' where service_order_id = 'd5000000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_prometido_tipo_check'),
  ('planejamento', 'tipo sem a data', $q$update public.os_planejamento set prometido_tipo = 'firme' where service_order_id = 'd5000000-0000-4000-8000-0000000000e3'$q$, 'prometido_coerente'),
  ('planejamento', 'data sem o tipo', $q$update public.os_planejamento set prometido_ate = '2026-11-05' where service_order_id = 'd5000000-0000-4000-8000-0000000000e3'$q$, 'prometido_coerente'),
  ('planejamento', 'faixa ao contrário', $q$update public.os_planejamento set prometido_tipo = 'faixa', prometido_de = '2026-11-06', prometido_ate = '2026-11-05' where service_order_id = 'd5000000-0000-4000-8000-0000000000e3'$q$, 'prometido_faixa'),
  ('planejamento', 'original sem a promessa', $q$update public.os_planejamento set prometido_original_ate = '2026-11-05' where service_order_id = 'd5000000-0000-4000-8000-0000000000e3'$q$, 'prometido_original'),
  ('planejamento', 'fonte fora da lista', $q$update public.os_planejamento set prometido_fonte = 'chute' where service_order_id = 'd5000000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_prometido_fonte_check'),
  ('planejamento', 'serviço de 2 letras', $q$update public.os_planejamento set servico_cliente = 'ok' where service_order_id = 'd5000000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_servico_cliente_check'),
  ('planejamento', 'serviço de 81 letras', $q$update public.os_planejamento set servico_cliente = repeat('a', 81) where service_order_id = 'd5000000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_servico_cliente_check'),
  ('planejamento', 'a faixa dita pelo dono, com o original e o serviço',
   $q$update public.os_planejamento set prometido_tipo = 'faixa', prometido_de = '2026-11-04', prometido_ate = '2026-11-06', prometido_original_ate = '2026-11-06', prometido_fonte = 'dono', prometido_em = now(), servico_cliente = 'a instalação do compressor', acesso_ok_em = now() where service_order_id = 'd5000000-0000-4000-8000-0000000000e3'$q$, 'aceitou'),
  -- agenda_cliente_mensagens
  ('mensagem', 'tipo fora da lista', pg_temp.msg('{"tipo": "cobranca"}'), 'agenda_cliente_mensagens_tipo_check'),
  ('mensagem', 'variante de 31', pg_temp.msg(jsonb_build_object('variante', repeat('x', 31))), 'agenda_cliente_mensagens_variante_check'),
  ('mensagem', 'origem fora da lista', pg_temp.msg('{"origem": "assistente"}'), 'agenda_cliente_mensagens_origem_check'),
  ('mensagem', 'modo desligado', pg_temp.msg('{"modo": "desligado"}'), 'agenda_cliente_mensagens_modo_check'),
  ('mensagem', 'texto de 2', pg_temp.msg('{"texto": "oi"}'), 'agenda_cliente_mensagens_texto_check'),
  ('mensagem', 'texto de 601', pg_temp.msg(jsonb_build_object('texto', repeat('x', 601))), 'agenda_cliente_mensagens_texto_check'),
  ('mensagem', 'base que não é objeto', pg_temp.msg('{"base": []}'), 'agenda_cliente_mensagens_base_check'),
  ('mensagem', 'prometido fora da lista', pg_temp.msg('{"prometido_tipo": "talvez"}'), 'agenda_cliente_mensagens_prometido_tipo_check'),
  ('mensagem', 'aprovação fora da lista', pg_temp.msg('{"aprovacao": "talvez"}'), 'agenda_cliente_mensagens_aprovacao_check'),
  ('mensagem', 'estado fora da lista', pg_temp.msg('{"estado": "perdida"}'), 'agenda_cliente_mensagens_estado_check'),
  ('mensagem', 'motivo fora da lista', pg_temp.msg('{"estado": "recusada", "recusa_motivo": "chuva"}'), 'agenda_cliente_mensagens_recusa_motivo_check'),
  ('mensagem', 'recusada sem motivo', pg_temp.msg('{"estado": "recusada"}'), 'cliente_recusa_coerente'),
  ('mensagem', 'motivo sem a recusa', pg_temp.msg('{"recusa_motivo": "janela"}'), 'cliente_recusa_coerente'),
  ('mensagem', 'faixa ao contrário', pg_temp.msg('{"faixa_de": "2026-11-06", "faixa_ate": "2026-11-05"}'), 'cliente_faixa_coerente'),
  ('mensagem', 'aprovada sem a hora', pg_temp.msg('{"aprovacao": "aprovada"}'), 'cliente_aprovacao_coerente'),
  ('mensagem', 'livre com a hora da aprovação', pg_temp.msg('{"aprovada_em": "2026-10-30 17:00-03"}'), 'cliente_aprovacao_coerente'),
  ('mensagem', 'pedida em ligado sem a pergunta', pg_temp.msg('{"modo": "ligado", "aprovacao": "pedida", "estado": "aguardando_dono"}'), 'cliente_critica_pergunta'),
  ('mensagem', 'crítica em ligado sem a pergunta', pg_temp.msg('{"modo": "ligado", "aprovacao": "critica", "estado": "aguardando_dono"}'), 'cliente_critica_pergunta'),
  ('mensagem', 'pedida em sombra sem a pergunta (em teste não pergunta)', pg_temp.msg('{"aprovacao": "pedida"}'), 'aceitou'),
  ('mensagem', 'enviada sem a hora', pg_temp.msg('{"modo": "ligado", "estado": "enviada"}'), 'cliente_enviada_coerente'),
  ('mensagem', 'registrada com a hora do envio', pg_temp.msg('{"enviada_em": "2026-10-31 09:00-03"}'), 'cliente_enviada_coerente'),
  ('mensagem', 'a mesma chave', pg_temp.msg('{"dedupe_key": "agenda-cliente:teste:1:sombra"}'), 'agenda_cliente_mensagens_dedupe_key_key'),
  ('mensagem', 'cliente que não existe', pg_temp.msg('{"client_id": "d5000000-0000-4000-8000-0000000000ff"}'), 'agenda_cliente_mensagens_client_id_fkey'),
  ('mensagem', 'OS que não existe', pg_temp.msg('{"service_order_id": "d5000000-0000-4000-8000-0000000000ff"}'), 'agenda_cliente_mensagens_service_order_id_fkey'),
  ('mensagem', 'pergunta que não existe', pg_temp.msg('{"modo": "ligado", "aprovacao": "pedida", "pergunta_id": "d5000000-0000-4000-8000-0000000000ff"}'), 'agenda_cliente_mensagens_pergunta_id_fkey'),
  ('mensagem', 'sem a hora de enviar', pg_temp.msg('{"enviar_em": null}'), '23502'),
  ('mensagem', 'enviada em ligado, aprovada, com a fila', pg_temp.msg('{"modo": "ligado", "estado": "enviada", "enviada_em": "2026-10-31 09:00:40-03", "aprovacao": "aprovada", "aprovada_em": "2026-10-30 17:40-03", "fila_id": "d5000000-0000-4000-8000-0000000000f0", "prometido_tipo": "firme", "dia_alvo": "2026-11-03"}'), 'aceitou'),
  -- agenda_cliente_respostas
  ('resposta', 'tipo da mensagem fora da lista', pg_temp.resp('{"tipo_msg": "sticker"}'), 'agenda_cliente_respostas_tipo_msg_check'),
  ('resposta', 'intenção fora da lista', pg_temp.resp('{"intencao": "elogio"}'), 'agenda_cliente_respostas_intencao_check'),
  ('resposta', 'efeito fora da lista', pg_temp.resp('{"efeito": "respondeu"}'), 'agenda_cliente_respostas_efeito_check'),
  ('resposta', 'modo desligado', pg_temp.resp('{"modo": "desligado"}'), 'agenda_cliente_respostas_modo_check'),
  ('resposta', 'texto de 501', pg_temp.resp(jsonb_build_object('texto', repeat('x', 501))), 'agenda_cliente_respostas_texto_check'),
  ('resposta', 'expressão de 61', pg_temp.resp(jsonb_build_object('expressao', repeat('x', 61))), 'agenda_cliente_respostas_expressao_check'),
  ('resposta', 'a mesma mensagem do WhatsApp', pg_temp.resp('{"whatsapp_message_id": "d5000000-0000-4000-8000-0000000000c3"}'), 'agenda_cliente_respostas_whatsapp_message_id_key'),
  ('resposta', 'cliente que não existe', pg_temp.resp('{"client_id": "d5000000-0000-4000-8000-0000000000ff"}'), 'agenda_cliente_respostas_client_id_fkey'),
  ('resposta', 'sem a hora', pg_temp.resp('{"recebida_em": null}'), '23502'),
  ('resposta', 'o áudio que foi ao dono, ligado à mensagem', pg_temp.resp('{"tipo_msg": "audio", "texto": null, "intencao": "audio", "efeito": "ao_dono", "modo": "ligado", "mensagem_id": "d5000000-0000-4000-8000-0000000000c1"}'), 'aceitou'),
  -- as listas fechadas ampliadas
  ('lista', 'pergunta cliente_aprovar entra (sem opções: não é crítica)', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('cliente_aprovar', 'cliente_aprovar:teste', 'Mensagem para o Teste: manda?', 'ligado')$q$, 'aceitou'),
  ('lista', 'pergunta cliente_resposta entra', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('cliente_resposta', 'cliente_resposta:teste', 'O Teste respondeu por áudio.', 'ligado')$q$, 'aceitou'),
  ('lista', 'pergunta cliente_aviso sem opções (é crítica)', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('cliente_aviso', 'cliente_aviso:teste', 'Vai atrasar de novo.', 'ligado')$q$, 'critica_tem_opcoes'),
  ('lista', 'pergunta cliente_aviso com as 3 opções e a recomendação', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao) values ('cliente_aviso', 'cliente_aviso:teste', 'Vai atrasar de novo.', 'ligado', '[{"n":1,"texto":"Você liga"},{"n":2,"texto":"Eu mando"},{"n":3,"texto":"Não aviso"}]', 1)$q$, 'aceitou'),
  ('lista', 'pergunta de tipo que não existe', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('cliente_cobrar', 'cliente_cobrar:teste', 'Cobro?', 'ligado')$q$, 'agenda_perguntas_tipo_check'),
  ('lista', 'ação cliente de origem cliente entra', $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto) values ('2026-10-30', true, 'cliente', 'cliente', 'O Teste confirmou ter 03/11.')$q$, 'aceitou'),
  ('lista', 'ação cliente da vigia (o envio) entra', $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto) values ('2026-10-30', true, 'vigia', 'cliente', 'Mandei ao Teste a confirmação de ter 03/11.')$q$, 'aceitou'),
  ('lista', 'ação de tipo que não existe', $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto) values ('2026-10-30', true, 'cliente', 'cobrar', 'Cobrei o Teste.')$q$, 'agenda_acoes_tipo_check'),
  ('lista', 'ação de origem que não existe', $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto) values ('2026-10-30', true, 'whatsapp', 'cliente', 'O Teste confirmou.')$q$, 'agenda_acoes_origem_check'),
  ('lista', 'rodada cliente entra', $q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('cliente', '2026-10-30', now(), 'sombra', 'sombra')$q$, 'aceitou'),
  ('lista', 'rodada de rotina que não existe', $q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('clientes', '2026-10-30', now(), 'sombra', 'sombra')$q$, 'agenda_vigia_rodadas_rotina_check'),
  ('lista', 'rascunho continua sem tipo novo (o prometido entra no planejar)', $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, expira_em) values ('d5000000-0000-4000-8000-0000000000ff', 'whatsapp', 'cliente', 'cliente:x', '{}', 'x', now() + interval '1 hour')$q$, 'agenda_rascunho_tipo_check');

insert into _resultado
select format('B1 %s: %s', k.grupo, k.nome), r = k.espera, r
  from _casos k, lateral (select pg_temp.recusa(k.sql) as r) x;

insert into _resultado
select 'B1z todo CHECK novo de agenda_config tem caso (nenhum ficou sem prova)',
       bool_and(exists (select 1 from _casos k where k.espera = c.conname)) and count(*) = 26,
       format('%s CHECKs; sem caso: %s', count(*),
              coalesce(string_agg(c.conname, ', ') filter (where not exists (select 1 from _casos k where k.espera = c.conname)), '—'))
  from pg_constraint c
 where c.conrelid = 'public.agenda_config'::regclass and c.contype = 'c'
   and c.conname ~ '^agenda_config_(modo_cliente|cliente_)';

insert into _resultado
select 'B1z os 3 CHECKs nomeados de os_planejamento e os 3 de coluna têm caso',
       bool_and(exists (select 1 from _casos k where k.espera = c.conname)) and count(*) = 6,
       string_agg(c.conname, ', ' order by c.conname)
  from pg_constraint c
 where c.conrelid = 'public.os_planejamento'::regclass and c.contype = 'c'
   and c.conname in ('prometido_coerente', 'prometido_faixa', 'prometido_original', 'os_planejamento_prometido_tipo_check',
                     'os_planejamento_prometido_fonte_check', 'os_planejamento_servico_cliente_check');

do $b1y$
declare
  v_res jsonb := '[]'::jsonb;
  v text;
begin
  begin
    for v in select unnest(array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data',
                                 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']) loop
      execute pg_temp.msg(jsonb_build_object('tipo', v, 'dedupe_key', 'agenda-cliente:modelo:' || v));
    end loop;
    v := (select string_agg(tipo || '=' || modelo, ',' order by tipo) from public.agenda_cliente_mensagens
           where dedupe_key like 'agenda-cliente:modelo:%');
    v_res := pg_temp.ok(v_res, 'B1y o modelo gerado: M1 a M10 (o pronto e o lembrete são os dois M8); a mensagem nasce registrada',
      v = 'acesso=M4,andamento=M5,confirmar=M1,material_chegou=M3,mudanca_no_dia=M10,nova_data=M7,pode_atrasar=M6,'
          || 'pos_servico=M9,pronto=M8,pronto_lembrete=M8,vespera=M2'
      and (select bool_and(estado = 'registrada') from public.agenda_cliente_mensagens where dedupe_key like 'agenda-cliente:modelo:%'),
      v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b1y$;

-- ── B2. RLS e privilégios ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B2a as 2 tabelas: RLS ligada e uma policy só, de leitura, TO authenticated',
       bool_and(c.relrowsecurity)
       and bool_and((select count(*) from pg_policy p where p.polrelid = c.oid) = 1)
       and bool_and((select bool_and(p.polcmd = 'r' and p.polroles = array[(select oid from pg_roles where rolname = 'authenticated')])
                       from pg_policy p where p.polrelid = c.oid)),
       string_agg(c.relname, ', ')
  from pg_class c
 where c.oid in ('public.agenda_cliente_mensagens'::regclass, 'public.agenda_cliente_respostas'::regclass);

insert into _resultado
select 'B2b anon sem privilégio nenhum; authenticated só lê; service_role escreve',
       bool_and(not has_table_privilege('anon', t, 'select') and not has_table_privilege('anon', t, 'insert')
                and not has_table_privilege('anon', t, 'update') and not has_table_privilege('anon', t, 'delete'))
       and bool_and(has_table_privilege('authenticated', t, 'select') and not has_table_privilege('authenticated', t, 'insert')
                    and not has_table_privilege('authenticated', t, 'update') and not has_table_privilege('authenticated', t, 'delete'))
       and bool_and(has_table_privilege('service_role', t, 'insert') and has_table_privilege('service_role', t, 'update')),
       null
  from unnest(array['public.agenda_cliente_mensagens', 'public.agenda_cliente_respostas']) t;

create temp table _funcoes_f5 (f text primary key, quem text) on commit drop;
insert into _funcoes_f5 values
  ('public._agenda_cliente_dia(date)', 'leitura'), ('public._agenda_cliente_dia_relativo(date, date)', 'leitura'),
  ('public._agenda_cliente_faixa(date, date, boolean)', 'leitura'), ('public._agenda_cliente_janela(uuid, date)', 'leitura'),
  ('public._agenda_cliente_telefone(uuid)', 'leitura'), ('public._agenda_cliente_contexto(uuid, date)', 'leitura'),
  ('public._agenda_cliente_texto(text, text, uuid, jsonb, date)', 'leitura'),
  ('public._agenda_cliente_texto_proibido(text)', 'leitura'),
  ('public._agenda_cliente_gravar_prometido(uuid, text, date, date, text, uuid, timestamptz, text)', 'interna'),
  ('public._agenda_cliente_prometer(uuid, timestamptz)', 'interna'),
  ('public._agenda_cliente_prometer_confirmacao(uuid, timestamptz, timestamptz)', 'interna'),
  ('public._agenda_cliente_mensagens_so_muda()', 'gatilho'), ('public._agenda_cliente_respostas_so_muda()', 'gatilho');

insert into _resultado
select 'B2c funções: anon nada; authenticated e service_role só as leituras; as internas (o prometido) sem grant a ninguém, nem service_role; os gatilhos sem authenticated',
       bool_and(not has_function_privilege('anon', f, 'execute'))
       and bool_and(has_function_privilege('authenticated', f, 'execute') = (quem = 'leitura'))
       and bool_and(has_function_privilege('service_role', f, 'execute') = (quem = 'leitura') or quem = 'gatilho'),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f, 'execute')
                                      or has_function_privilege('authenticated', f, 'execute') <> (quem = 'leitura')
                                      or not (has_function_privilege('service_role', f, 'execute') = (quem = 'leitura') or quem = 'gatilho'))
  from _funcoes_f5;

insert into _resultado
select 'B2d security definer só as 3 que gravam o prometido; leituras STABLE/IMMUTABLE; search_path fixo em todas',
       bool_and(p.prosecdef = (k.quem = 'interna'))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and bool_and(p.provolatile in ('s', 'i') or k.quem <> 'leitura'),
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ' order by p.proname)
  from _funcoes_f5 k join pg_proc p on p.oid = k.f::regprocedure;

insert into _resultado
select 'B2e o técnico: as tabelas voltam vazias e gravar o prometido dá 42501; anon não lê; o administrador lê',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select (select count(*) from public.agenda_cliente_mensagens) + (select count(*) from public.agenda_cliente_respostas)$q$) = '0'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select public._agenda_cliente_prometer('d5000000-0000-4000-8000-0000000000c1', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select public._agenda_cliente_prometer_confirmacao('d5000000-0000-4000-8000-0000000000e3', now(), now())::text$q$) like 'erro 42501%'
       and pg_temp.como(null, 'anon', $q$select count(*)::text from public.agenda_cliente_mensagens$q$) like 'erro 42501%'
       and pg_temp.como(null, 'anon', $q$select public._agenda_cliente_texto_proibido('oi')$q$) like 'erro 42501%'
       and pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated',
             $q$select (select count(*) from public.agenda_cliente_mensagens where id = 'd5000000-0000-4000-8000-0000000000c1')
                       + (select count(*) from public.agenda_cliente_respostas where id = 'd5000000-0000-4000-8000-0000000000c2')$q$) = '2',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select public._agenda_cliente_prometer('d5000000-0000-4000-8000-0000000000c1', now())::text$q$);

-- ── B3. A coluna gerada critica com cliente_aviso ───────────────────────────────────────────────────────
insert into _resultado
select 'B3a agenda_perguntas.critica: gerada (stored), com cliente_aviso e as 6 de antes, no mesmo lugar (antes de chave)',
       a.attgenerated = 's'
       and pg_get_expr(d.adbin, d.adrelid) like '%''cliente_aviso''%'
       and pg_get_expr(d.adbin, d.adrelid) !~ 'cliente_aprovar|cliente_resposta'
       and (select bool_and(pg_get_expr(d.adbin, d.adrelid) like '%''' || t || '''%')
              from unnest(array['nao_cabe', 'segundo_atraso', 'atraso_longo', 'remarcar_confirmado', 'fixada_pelo_dono', 'diaria']) t)
       and a.attnum < (select x.attnum from pg_attribute x where x.attrelid = a.attrelid and x.attname = 'chave'),
       format('attnum %s: %s', a.attnum, pg_get_expr(d.adbin, d.adrelid))
  from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica';

insert into _resultado
select 'B3b critica_tem_opcoes e critica_decidida continuam, lendo critica',
       count(*) = 2 and bool_and(pg_get_constraintdef(c.oid) like '%critica%'),
       string_agg(c.conname, ', ')
  from pg_constraint c
 where c.conrelid = 'public.agenda_perguntas'::regclass and c.conname in ('critica_tem_opcoes', 'critica_decidida');

do $b3$
declare
  v_res jsonb := '[]'::jsonb;
  r record;
  v_det text := '';
  v_ok boolean := true;
begin
  begin
    for r in select * from (values ('cliente_aviso', true), ('cliente_aprovar', false), ('cliente_resposta', false),
                                   ('diaria', true), ('nao_cabe', true), ('concluir', false), ('nfe_vincular', false)) as t(tipo, critica)
    loop
      insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao)
      values (r.tipo, r.tipo || ':ag5', 'Pergunta de teste.', 'ligado',
              case when r.critica then '[{"n":1},{"n":2},{"n":3}]'::jsonb else '[]'::jsonb end, case when r.critica then 1 end);
      if (select p.critica from public.agenda_perguntas p where p.chave = r.tipo || ':ag5') is distinct from r.critica then
        v_ok := false;
        v_det := v_det || r.tipo || ' ';
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'B3c critica por tipo: cliente_aviso, diaria e nao_cabe sim; cliente_aprovar, cliente_resposta, concluir e nfe_vincular não',
                        v_ok, nullif(v_det, ''));
    -- a crítica respondida sem a opção é recusada (critica_decidida vale para o tipo novo)
    v_res := pg_temp.ok(v_res, 'B3d cliente_aviso respondida sem a opção é recusada (critica_decidida)',
      pg_temp.recusa($q$update public.agenda_perguntas set estado = 'respondida', respondida_em = now() where chave = 'cliente_aviso:ag5'$q$)
        = 'critica_decidida');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b3$;

-- ── B4. Os registros não se apagam e só mudam no estado ─────────────────────────────────────────────────
do $b4$
declare
  v_res jsonb := '[]'::jsonb;
  c_msg  constant uuid := 'd5000000-0000-4000-8000-0000000000c1';
  c_resp constant uuid := 'd5000000-0000-4000-8000-0000000000c2';
  m public.agenda_cliente_mensagens;
begin
  begin
    v_res := pg_temp.ok(v_res, 'B4a a mensagem não se apaga; a resposta também não',
      pg_temp.recusa(format('delete from public.agenda_cliente_mensagens where id = %L', c_msg)) = 'erro P0001: O registro da agenda não se apaga.'
      and pg_temp.recusa(format('delete from public.agenda_cliente_respostas where id = %L', c_resp)) = 'erro P0001: O registro da agenda não se apaga.');
    v_res := pg_temp.ok(v_res, 'B4b o texto, o tipo, o cliente, o modo, a chave, a base e a validade da mensagem não mudam',
      (select bool_and(pg_temp.recusa(format('update public.agenda_cliente_mensagens set %s where id = %L', s, c_msg))
                       = 'erro P0001: A mensagem ao cliente registrada não muda: só o estado, a aprovação, a fila, o envio e a resposta.')
         from unnest(array[$s$texto = 'Outro texto qualquer.'$s$, $s$tipo = 'vespera'$s$,
                           $s$client_id = 'c1000000-0000-4000-8000-000000000004'$s$, $s$modo = 'ligado'$s$,
                           $s$dedupe_key = 'agenda-cliente:outra'$s$, $s$base = '{"dia_alvo": "2026-11-04"}'$s$,
                           $s$valida_ate = valida_ate + interval '1 day'$s$, $s$dia_alvo = '2026-11-04'$s$]) s));
    -- a espera da conversa viva: a hora muda enquanto registrada
    update public.agenda_cliente_mensagens set enviar_em = enviar_em + interval '1 hour' where id = c_msg;
    select * into m from public.agenda_cliente_mensagens where id = c_msg;
    v_res := pg_temp.ok(v_res, 'B4c a hora muda enquanto a mensagem está registrada (a conversa viva empurra)',
      m.enviar_em = timestamptz '2026-10-31 10:00-03', m.enviar_em::text);
    update public.agenda_cliente_mensagens set estado = 'aguardando_dono' where id = c_msg;
    update public.agenda_cliente_mensagens set enviar_em = enviar_em + interval '1 hour' where id = c_msg;
    update public.agenda_cliente_mensagens
       set estado = 'enfileirada', fila_id = 'd5000000-0000-4000-8000-0000000000f1', aprovacao = 'aprovada',
           aprovada_em = timestamptz '2026-10-30 17:40-03', aprovada_por = 'aa000000-0000-4000-8000-000000000001'
     where id = c_msg;
    v_res := pg_temp.ok(v_res, 'B4d enfileirada, a hora não muda mais',
      pg_temp.recusa(format('update public.agenda_cliente_mensagens set enviar_em = enviar_em + interval ''1 hour'' where id = %L', c_msg))
        = 'erro P0001: A hora da mensagem ao cliente só muda enquanto ela espera (registrada ou esperando o dono).');
    update public.agenda_cliente_mensagens
       set estado = 'enviada', enviada_em = timestamptz '2026-10-31 11:00:40-03', resposta_id = c_resp
     where id = c_msg;
    select * into m from public.agenda_cliente_mensagens where id = c_msg;
    v_res := pg_temp.ok(v_res, 'B4e o estado, a fila, a aprovação, o envio e a resposta mudam',
      m.estado = 'enviada' and m.fila_id = 'd5000000-0000-4000-8000-0000000000f1' and m.aprovacao = 'aprovada'
      and m.enviada_em = timestamptz '2026-10-31 11:00:40-03' and m.resposta_id = c_resp
      and m.enviar_em = timestamptz '2026-10-31 11:00-03' and m.modelo = 'M1', to_jsonb(m)::text);
    -- a resposta: só o efeito, a ação, a pergunta e a data dita
    v_res := pg_temp.ok(v_res, 'B4f o texto, a intenção, quem mandou e quando da resposta não mudam',
      (select bool_and(pg_temp.recusa(format('update public.agenda_cliente_respostas set %s where id = %L', s, c_resp))
                       = 'erro P0001: A resposta do cliente registrada não muda: só o efeito, a ação, a pergunta e a data dita.')
         from unnest(array[$s$texto = 'não'$s$, $s$intencao = 'remarcar'$s$, $s$recebida_em = now()$s$,
                           $s$client_id = 'c1000000-0000-4000-8000-000000000004'$s$, $s$modo = 'ligado'$s$]) s));
    update public.agenda_cliente_respostas
       set efeito = 'ao_dono', data_dita = date '2026-11-06',
           acao_id = (select a.id from public.agenda_acoes a order by a.criada_em limit 1)
     where id = c_resp;
    v_res := pg_temp.ok(v_res, 'B4g o efeito, a ação e a data dita da resposta mudam',
      (select efeito = 'ao_dono' and data_dita = date '2026-11-06' from public.agenda_cliente_respostas where id = c_resp));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b4$;

-- ── B5. O espelho da Fase 2 continua o mesmo; a Fase 5 lê o plano e não escreve o espelho ───────────────
do $b5$
declare
  v_res jsonb := '[]'::jsonb;
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_fla   constant uuid := '05000000-0000-4000-8000-000000000104';
  c_ven   constant uuid := '05000000-0000-4000-8000-000000000069';
  c_hoje  constant date := date '2026-10-30';
  v_antes text;
  v_dep   text;
  r jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('B5 o espelho e a Fase 5 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase5');
    v_res := pg_temp.ok(v_res, 'B5a publicar → o espelho é o começo do 1º e o fim do último meio-dia vigente, nas 4 OS publicadas',
      (select bool_and(so.scheduled_start_at = x.mn and so.scheduled_end_at = x.mx) and count(*) = 4
         from public.service_orders so
         join (select a.service_order_id, min(lower(a.periodo)) as mn, max(upper(a.periodo)) as mx from public.agenda_alocacoes a
                where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido'
                group by 1) x on x.service_order_id = so.id),
      (select string_agg(so.service_order_number || ' ' || so.scheduled_start_at || '–' || so.scheduled_end_at, '; ')
         from public.service_orders so where so.scheduled_start_at is not null));
    v_res := pg_temp.ok(v_res, 'B5b o espelho do Flávio já está certo: espelhar de novo não muda nada',
      not (public._agenda_espelhar_datas(c_fla, c_hoje) ->> 'mudou')::boolean);

    -- A Fase 5 lê e grava o prometido; o espelho (e o status) das OS não mexe.
    v_antes := (select md5(string_agg(so.id || coalesce(so.scheduled_start_at::text, '-') || coalesce(so.scheduled_end_at::text, '-')
                                      || so.status, ',' order by so.id)) from public.service_orders so);
    perform public._agenda_cliente_texto(t, v, so.id, '{"quando": "hoje", "n_feitos": 1, "faixa_de": "2026-11-12", "peca_de": "2026-11-11", "dia_dito": "2026-11-05", "primeira": false}', c_hoje)
       from public.service_orders so
      cross join (values ('confirmar', null), ('vespera', null), ('pronto', null), ('andamento', 'semanal'),
                         ('pode_atrasar', 'peca'), ('mudanca_no_dia', 'clima')) k(t, v)
      where so.id in (c_fla, c_ven);
    perform public._agenda_cliente_prometer('d5000000-0000-4000-8000-0000000000a1', timestamptz '2026-10-30 10:00-03');
    perform public._agenda_cliente_prometer_confirmacao(c_ven, timestamptz '2026-11-03 08:00-03', timestamptz '2026-10-30 10:00-03');
    perform public._agenda_cliente_gravar_prometido(c_fla, 'firme', date '2026-11-03', date '2026-11-04', 'dono', null,
                                                    timestamptz '2026-10-30 10:00-03', 'falei pro Flávio que é dia 3');
    v_dep := (select md5(string_agg(so.id || coalesce(so.scheduled_start_at::text, '-') || coalesce(so.scheduled_end_at::text, '-')
                                    || so.status, ',' order by so.id)) from public.service_orders so);
    v_res := pg_temp.ok(v_res, 'B5c os textos, o contexto e as 3 gravações do prometido não mexem no espelho nem no status de OS nenhuma',
      v_antes = v_dep and (select prometido_tipo = 'firme' and prometido_fonte = 'confirmacao'
                             from public.os_planejamento where service_order_id = c_ven));

    -- O contexto lê o plano, não o espelho: o espelho do Vanderlei escrito à mão (pela chave da porta) não muda o dia.
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set scheduled_start_at = timestamptz '2026-11-20 08:00-03',
                                     scheduled_end_at = timestamptz '2026-11-20 17:00-03'
     where id = c_ven;
    perform set_config('agenda.porta', 'off', true);
    r := public._agenda_cliente_contexto(c_ven, c_hoje);
    v_res := pg_temp.ok(v_res, 'B5d o contexto lê o plano (ter 03/11 a qui 05/11), não o espelho (escrito à mão para sex 20/11)',
      r ->> 'dia' = '2026-11-03' and r ->> 'fim' = '2026-11-05', r::text);

    -- desfazer → o espelho volta (o Flávio sai da agenda: sem plano, as datas ficam nulas) e o contexto fica sem dia
    r := public.agenda_desfazer((select a.id from public.agenda_acoes a where a.tipo = 'publicar' and a.service_order_id = c_fla),
                                c_admin, 'dono', c_hoje, timestamptz '2026-10-30 10:00-03');
    v_res := pg_temp.ok(v_res, 'B5e desfazer a publicação → o espelho volta (nulo, sem plano) e o contexto fica sem dia; o prometido dito fica',
      (select scheduled_start_at is null and scheduled_end_at is null and status = 'awaiting_parts' from public.service_orders where id = c_fla)
      and public._agenda_cliente_contexto(c_fla, c_hoje) ->> 'dia' is null
      and (select prometido_ate = date '2026-11-04' from public.os_planejamento where service_order_id = c_fla),
      r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b5$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
