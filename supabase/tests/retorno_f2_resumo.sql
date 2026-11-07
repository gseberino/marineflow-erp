-- Retorno F2 (P12): retorno_resumo_extra e a lista da auditoria. Relógio fixo em novembro de 2026. Roda só pela bancada.
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000091xx; a frase marcada é inventada.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f2r_saida(p_caso uuid, p_tipo text, p_letra text, p_dia date, p_em timestamptz, p_chave text, p_dados jsonb default '{"sozinho": true}')
returns uuid
language sql as $f$
  insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, decidida_em, enviada_em, texto, letra, letra_dia, dados, dedupe_key)
  select a.id, p_tipo, 'retorno_modelo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', 'enviada', p_em, p_em, p_em, 'Texto automático do modelo.', p_letra, p_dia, p_dados, p_chave
    from public.retorno_aberturas a where a.id = p_caso
  returning id
$f$;

do $resumo$
declare
  c_tarde constant timestamptz := '2026-11-10 17:30:00-03';   -- terça
  v_cl uuid;
  v_msg uuid;
  v_caso uuid;
  v_r jsonb;
  v_n integer;
begin
  begin
    update public.retorno_config set modo = 'sombra', cartao_ligado = true;
    insert into public.clients (type, name, whatsapp) values ('individual', 'Rodrigo Resumo Teste', '(47) 90000-9110') returning id into v_cl;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('inbound', '5547900009110', 'text', 'FRASE-MARCADA-F2 como tá o motorhome?', 'received', '{"data": {}}'::jsonb, '2026-11-10 09:00-03', '2026-11-10 09:00-03')
    returning id into v_msg;
    insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em, gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
    values (public._agenda_chave_telefone('5547900009110'), '5547900009110', '47', 'cliente', '{"papel": "cliente"}', v_cl, v_msg, v_msg,
            '2026-11-10 09:00-03', '2026-11-10 09:00-03', '2026-11-10 09:00-03', '2026-11-10 09:00-03', 'recibo', 'recibo_cliente', 'aberta', 'sombra')
    returning id into v_caso;
    insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta)
    values (v_msg, v_caso, public._agenda_chave_telefone('5547900009110'), '2026-11-10 09:00-03', '2026-11-10 09:00-03', 'x', true);

    -- Letras Z, Y e X na ordem delas; o que veio antes do fechamento anterior não entra; o que passou de 3 conta à parte.
    perform pg_temp.f2r_saida(v_caso, 'modelo_aguarda_peca', 'Y', '2026-11-10', '2026-11-10 11:00-03', 'teste-f2-res:y');
    perform pg_temp.f2r_saida(v_caso, 'modelo_pronto', 'Z', '2026-11-10', '2026-11-10 10:00-03', 'teste-f2-res:z');
    perform pg_temp.f2r_saida(v_caso, 'modelo_peca_chegou', 'X', '2026-11-10', '2026-11-10 12:00-03', 'teste-f2-res:x');
    perform pg_temp.f2r_saida(v_caso, 'modelo_em_servico', 'W', '2026-11-10', '2026-11-10 13:00-03', 'teste-f2-res:w');
    perform pg_temp.f2r_saida(v_caso, 'modelo_liberado', 'V', '2026-11-09', '2026-11-09 10:00-03', 'teste-f2-res:antiga');
    perform pg_temp.f2r_saida(v_caso, 'modelo_pronto', null, null, '2026-11-10 14:00-03', 'teste-f2-res:aprovada', '{"aprovada": true}');
    v_r := public.retorno_resumo_extra('fechamento', c_tarde);
    if (select string_agg(e ->> 'letra', '' order by ord) from jsonb_array_elements(v_r -> 'mandei') with ordinality as x(e, ord)) is distinct from 'ZYX' then
      raise exception '1a: letras (%)', v_r -> 'mandei';
    end if;
    if (v_r ->> 'mandei_mais')::integer <> 1 then
      raise exception '1b: mandei_mais (%)', v_r;
    end if;
    if (v_r -> 'mandei' -> 0 ->> 'tipo_curto') is distinct from 'pronto' or (v_r -> 'mandei' -> 0 ->> 'rotulo') is distinct from 'Rodrigo' then
      raise exception '1c: item (%)', v_r -> 'mandei' -> 0;
    end if;
    if public.retorno_resumo_extra('fechamento', c_tarde + interval '1 hour') -> 'mandei' is distinct from v_r -> 'mandei' then
      raise exception '1d: as letras mudaram no mesmo dia';
    end if;
    if v_r::text like '%FRASE-MARCADA%' then
      raise exception '2: texto do cliente no extra';
    end if;

    -- Promovido, rebaixado e suspenso.
    update public.retorno_modelo_tipos set nivel = 'sozinho', promovido_em = '2026-11-10 08:00-03' where tipo = 'modelo_pronto';
    update public.retorno_modelo_tipos set rebaixado_em = '2026-11-10 09:00-03', rebaixado_motivo = 'errado' where tipo = 'modelo_peca_chegou';
    update public.retorno_modelo_tipos set promocao_suspensa_ate = '2026-11-17 09:00-03' where tipo = 'modelo_liberado';
    v_r := public.retorno_resumo_extra('fechamento', c_tarde);
    if v_r -> 'promovidos' is distinct from '["pronto"]'::jsonb or v_r -> 'suspensos' is distinct from '["liberado"]'::jsonb
       or v_r -> 'rebaixados' -> 0 ->> 'motivo' is distinct from 'errado' then
      raise exception '3: extras (%)', v_r;
    end if;

    -- Manhã: contatos desde o fechamento anterior.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('inbound', '5547900009111', 'text', 'ofereço marketing', 'received', '{"data": {}}'::jsonb, '2026-11-10 20:00-03', '2026-11-10 20:00-03')
    returning id into v_msg;
    insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, primeira_msg_id, ultima_msg_id, aberta_em, gravada_em, ultima_em, ultima_gravada_em, nivel, motivo, estado, modo)
    values (public._agenda_chave_telefone('5547900009111'), '5547900009111', '47', 'numero_novo', '{"papel": "numero_novo"}', v_msg, v_msg,
            '2026-11-10 20:00-03', '2026-11-10 20:00-03', '2026-11-10 20:00-03', '2026-11-10 20:00-03', 'nada', 'vendedor', 'aberta', 'sombra');
    v_r := public.retorno_resumo_extra('manha', '2026-11-11 07:30-03');
    if v_r -> 'contatos' is distinct from '{"vendedores": 1, "conhecidos": 0}'::jsonb or not (v_r ->> 'palavra')::boolean then
      raise exception '4: manhã (%)', v_r;
    end if;

    -- A semana só na sexta.
    if public.retorno_resumo_extra('fechamento', c_tarde) -> 'semana' <> 'null'::jsonb then
      raise exception '5a: semana numa terça';
    end if;
    v_r := public.retorno_resumo_extra('fechamento', '2026-11-13 17:30-03');
    if v_r -> 'semana' = 'null'::jsonb or (v_r -> 'semana' ->> 'dias_uteis')::integer <> 5 then
      raise exception '5b: semana na sexta (%)', v_r -> 'semana';
    end if;

    -- A auditoria tem a pergunta do cliente, e por isso é fechada.
    update public.retorno_saidas set dados = dados || '{"auditoria": true}' where dedupe_key = 'teste-f2-res:z';
    select count(*) into v_n from public.retorno_auditoria_lista l where l.rotulo = 'Rodrigo';
    if v_n <> 3 then
      raise exception '6a: amostra e o que passou de 3 (%)', v_n;
    end if;
    begin
      set local role anon;
      perform 1 from public.retorno_auditoria_lista;
      reset role;
      raise exception '6b: anon leu a auditoria';
    exception when insufficient_privilege then
      reset role;
    end;

    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f2_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_resumo', true, '{}');
end
$resumo$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
