-- Retorno F3 (P4): os textos da proposta, a validade do envio e o caso que não fecha com a visita a combinar. Roda só pela bancada
-- (grupo 5). Termina em ROLLBACK, e o bloco se desfaz sozinho. Relógio em março de 2027 (o calendário de produção, como no teste do
-- vigia da F1): seg 01/03 a sex 05/03, seg 08/03 a sex 12/03. Telefones 55479009xxxxx; frases e nomes inventados.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f3t_caso(p_n integer, p_papel text, p_cliente uuid, p_corpo text, p_aberta timestamptz) returns uuid
language plpgsql as $f$
declare
  v_fone text := '55479009' || lpad(p_n::text, 5, '0');
  v_chave text := public._agenda_chave_telefone(v_fone);
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', v_fone, 'text', p_corpo, 'received', '{"data": {}}'::jsonb, p_aberta, p_aberta)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
  values (v_chave, v_fone, '47', p_papel, jsonb_build_object('papel', p_papel), p_cliente, v_msg, v_msg, p_aberta,
          p_aberta, p_aberta, p_aberta, 'recibo', 'recibo_cliente', 'aberta', 'sombra')
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, sinais, pede_resposta)
  values (v_msg, v_id, v_chave, p_aberta, p_aberta, md5(p_corpo), public._retorno_sinais(p_corpo), true);
  return v_id;
end $f$;

create or replace function pg_temp.f3t_cli(p_nome text, p_tipo text default 'individual') returns uuid
language sql as $f$
  insert into public.clients (type, name) values (p_tipo, p_nome) returning id;
$f$;

create or replace function pg_temp.f3t_igual(p_rot text, p_valor text, p_esp text) returns void
language plpgsql as $f$
begin
  if p_valor is distinct from p_esp then
    raise exception '%: %, esperava %', p_rot, coalesce(p_valor, '∅'), coalesce(p_esp, '∅');
  end if;
end $f$;

create or replace function pg_temp.f3t_proposta(p_caso uuid, p_cli uuid, p_familias text[], p_titulo text) returns uuid
language sql as $f$
  insert into public.retorno_previa (abertura_id, chave, client_id, origem, familias, titulo, estado, modo, hash)
  select a.id, a.chave, p_cli, 'historico', p_familias, p_titulo, 'proposta', 'ligado', 'x'
    from public.retorno_aberturas a where a.id = p_caso
  returning id;
$f$;

create or replace function pg_temp.f3t_saida(p_caso uuid, p_tipo text, p_estado text, p_em timestamptz, p_chave text default 'teste') returns uuid
language sql as $f$
  insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, decidida_em, texto, dados, dedupe_key)
  select a.id, p_tipo, 'aprovado', 'retorno_modelo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', p_estado, p_em,
         case when p_estado <> 'agendada' then p_em end, 'texto de teste',
         jsonb_build_object('aprovada', true, 'aprovada_em', p_em), 'teste-f3-textos:' || p_chave || ':' || a.id
    from public.retorno_aberturas a where a.id = p_caso
  returning id;
$f$;

create or replace function pg_temp.f3t_esperar_22023(p_tipo text, p_variante text, p_dados jsonb, p_rot text) returns void
language plpgsql as $f$
begin
  begin
    perform public._retorno_texto_f3(p_tipo, p_variante, p_dados);
  exception when others then
    if sqlstate <> '22023' then
      raise;
    end if;
    return;
  end;
  raise exception '%: devia dar 22023', p_rot;
end $f$;

do $textos$
declare
  c_agora constant timestamptz := '2027-03-08 10:00-03';   -- segunda
  c_servico constant text := 'das baterias';
  d_ok constant jsonb := '{"nome": "Rodrigo", "do_servico": "das baterias", "validade": "segunda (15/03)"}';
  c_apr constant text := 'Oi, Rodrigo! Aqui é a Claudia, assistente virtual da HBR. ';
  v_cl uuid; v_cl2 uuid; v_cl3 uuid; v_emp uuid;
  v_caso uuid; v_caso2 uuid; v_caso3 uuid; v_caso4 uuid;
  v_pv uuid;
  v_r jsonb;
  v_ctx jsonb;
  v_t text;
  v_saida uuid; v_saida2 uuid; v_saida3 uuid;
  v_ab public.retorno_aberturas;
  v_chaves text[];
  v_vig jsonb;
  c_t constant timestamptz := '2027-03-08 15:00-03';
begin
  begin
    update public.retorno_config
       set modo = 'sombra', tipos_ligados = '{}', previa_modo = 'ligado', previa_ditado_ligado = true, caso_fecha_silencio = interval '4 hours',
           expira_dias_uteis = 3, apresentacao_intervalo = interval '365 days', validade_orcamento_dias = 7
     where id;
    update public.whatsapp_conexao_vigia set estado = 'open', desde = '2027-01-01 00:00:00-03' where id = 1;

    -- ═══ 1. Cada variante literal.
    perform pg_temp.f3t_igual('1 padrao', public._retorno_texto_f3('orcamento_pdf', 'padrao', d_ok),
      'Rodrigo, segue o orçamento das baterias. Ele vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    perform pg_temp.f3t_igual('1 padrao_apresentacao', public._retorno_texto_f3('orcamento_pdf', 'padrao_apresentacao', d_ok),
      c_apr || 'Segue o orçamento das baterias, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    perform pg_temp.f3t_igual('1 sem_servico', public._retorno_texto_f3('orcamento_pdf', 'sem_servico', d_ok),
      'Rodrigo, segue o orçamento que você pediu. Ele vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    perform pg_temp.f3t_igual('1 sem_servico_apresentacao', public._retorno_texto_f3('orcamento_pdf', 'sem_servico_apresentacao', d_ok),
      c_apr || 'Segue o orçamento que você pediu, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    perform pg_temp.f3t_igual('1 sem_nome', public._retorno_texto_f3('orcamento_pdf', 'sem_nome', d_ok),
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento das baterias, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    perform pg_temp.f3t_igual('1 sem_nome_servico', public._retorno_texto_f3('orcamento_pdf', 'sem_nome_servico', d_ok),
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento que você pediu, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    perform pg_temp.f3t_igual('1 sem_nome_ja', public._retorno_texto_f3('orcamento_pdf', 'sem_nome_ja_apresentada', d_ok),
      'Segue o orçamento das baterias, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    perform pg_temp.f3t_igual('1 sem_nome_servico_ja', public._retorno_texto_f3('orcamento_pdf', 'sem_nome_servico_ja_apresentada', d_ok),
      'Segue o orçamento que você pediu, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');

    -- ═══ 2. Falta de campo, campo inválido e par desconhecido dão 22023.
    perform pg_temp.f3t_esperar_22023('orcamento_pdf', 'padrao', d_ok - 'validade', '2a sem validade');
    perform pg_temp.f3t_esperar_22023('orcamento_pdf', 'padrao', d_ok - 'nome', '2b sem nome');
    perform pg_temp.f3t_esperar_22023('orcamento_pdf', 'padrao', d_ok - 'do_servico', '2c sem do_servico');
    perform pg_temp.f3t_esperar_22023('orcamento_pdf', 'padrao', d_ok || '{"validade": "semana que vem"}', '2d validade fora da lista');
    perform pg_temp.f3t_esperar_22023('orcamento_pdf', 'nao_existe', d_ok, '2e variante desconhecida');
    perform pg_temp.f3t_esperar_22023('outro', 'padrao', d_ok, '2f tipo desconhecido');

    -- ═══ 3. Validade: 7 dias corridos do envio, em data de Brasília.
    perform pg_temp.f3t_igual('3a validade', public._retorno_validade_do_envio('2026-12-08 12:00-03')::text, '2026-12-15');
    perform pg_temp.f3t_igual('3b virada do dia em Brasília', public._retorno_validade_do_envio('2026-12-09 02:30+00')::text, '2026-12-15');

    -- ═══ 4. Legenda: com nome, sem apresentação ainda → L02; depois do PDF que saiu → L01.
    v_cl := pg_temp.f3t_cli('Rodrigo Legenda Teste');
    v_caso := pg_temp.f3t_caso(1, 'cliente', v_cl, 'FRASE-MARCADA-F3 quanto fica pra trocar as baterias?', c_agora - interval '2 hours');
    v_pv := pg_temp.f3t_proposta(v_caso, v_cl, array['bateria'], 'Baterias');
    if public._cliente_ja_apresentada(v_cl, public._agenda_chave_telefone('5547900900001'), '2027-03-08') then
      raise exception '4a: já apresentada antes do PDF';
    end if;
    v_r := public.retorno_legenda_do_orcamento(v_caso, v_pv, c_agora);
    perform pg_temp.f3t_igual('4b L02', v_r ->> 'texto',
      c_apr || 'Segue o orçamento das baterias, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    perform pg_temp.f3t_igual('4c validade_data', v_r ->> 'validade_data', '2027-03-15');
    v_ctx := v_r -> 'contexto';
    select array_agg(k order by k) into v_chaves from jsonb_object_keys(v_ctx) k;
    if v_chaves is distinct from array['audiencia', 'datas_permitidas', 'horas_permitidas', 'marcas', 'nome_permitido', 'nomes_de_outros',
                                       'os_permitidas', 'textos_do_cliente', 'trechos_do_modelo'] then
      raise exception '4d: chaves do contexto (%)', v_chaves;
    end if;
    if exists (select 1 from jsonb_each(v_ctx) e where jsonb_typeof(e.value) = 'null') then
      raise exception '4e: chave nula no contexto: %', v_ctx;
    end if;
    perform pg_temp.f3t_igual('4f nome_permitido', v_ctx ->> 'nome_permitido', 'Rodrigo');
    perform pg_temp.f3t_igual('4g audiencia', v_ctx ->> 'audiencia', 'cliente');
    if v_ctx -> 'datas_permitidas' is distinct from '["segunda (15/03)", "15/03"]'::jsonb
       or v_ctx -> 'horas_permitidas' is distinct from '[]'::jsonb
       or v_ctx -> 'nomes_de_outros' is distinct from '[]'::jsonb
       or v_ctx -> 'os_permitidas' is distinct from '[]'::jsonb then
      raise exception '4h: listas do contexto: %', v_ctx;
    end if;
    if (v_ctx -> 'marcas' ->> 'tem_proposta')::boolean is not true or (v_ctx -> 'marcas' ->> 'tem_topo')::boolean is not false
       or (v_ctx -> 'marcas' ->> 'cliente_ouviu')::boolean is not false or (v_ctx -> 'marcas' ->> 'conferida')::boolean is not false then
      raise exception '4i: marcas: %', v_ctx -> 'marcas';
    end if;
    perform pg_temp.f3t_igual('4j trechos (do maior valor para o menor)', v_ctx ->> 'trechos_do_modelo',
      '["Oi, ", "! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento das baterias, que vale até ", ". Se tiver dúvida ou quiser ajustar algo, é só responder por aqui."]');
    -- O texto do cliente fica só no eco do validador: nunca sobe ao texto da legenda.
    if (v_ctx -> 'textos_do_cliente' -> 0 ->> 0) not like 'FRASE-MARCADA-F3%' or v_r ->> 'texto' like '%FRASE-MARCADA%' then
      raise exception '4k: textos do cliente: %', v_ctx -> 'textos_do_cliente';
    end if;

    -- Ninguém olha o futuro: mensagem depois de p_agora não entra.
    perform 1 from jsonb_array_elements_text(public.retorno_legenda_do_orcamento(v_caso, v_pv, c_agora - interval '3 hours') -> 'contexto' -> 'textos_do_cliente');
    if found then
      raise exception '4l: o contexto olhou o futuro';
    end if;

    -- Depois do PDF que saiu, ao mesmo cliente: apresentação conta, e sai L01.
    update public.retorno_previa set pdf_em = c_agora - interval '1 hour' where id = v_pv;
    if not public._cliente_ja_apresentada(v_cl, 'xxxxxxxx', '2027-03-08') then
      raise exception '4m: pdf_em por cliente não contou';
    end if;
    if not public._cliente_ja_apresentada(null, (select a.chave from public.retorno_aberturas a where a.id = v_caso), '2027-03-08') then
      raise exception '4n: pdf_em por chave não contou';
    end if;
    v_r := public.retorno_legenda_do_orcamento(v_caso, v_pv, c_agora);
    perform pg_temp.f3t_igual('4o L01', v_r ->> 'texto',
      'Rodrigo, segue o orçamento das baterias. Ele vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');

    -- p_previa nulo: variantes sem serviço (L03 com apresentação já feita).
    v_r := public.retorno_legenda_do_orcamento(v_caso, null, c_agora);
    perform pg_temp.f3t_igual('4p L03', v_r ->> 'texto',
      'Rodrigo, segue o orçamento que você pediu. Ele vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');

    -- 3 famílias: do_servico nulo, variante sem serviço.
    update public.retorno_previa set familias = array['bateria', 'solar', 'inversor'] where id = v_pv;
    v_r := public.retorno_legenda_do_orcamento(v_caso, v_pv, c_agora);
    perform pg_temp.f3t_igual('4q 3 famílias', v_r ->> 'texto',
      'Rodrigo, segue o orçamento que você pediu. Ele vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    update public.retorno_previa set familias = array['bateria'] where id = v_pv;

    -- ═══ 5. Nome nulo: empresa sem display_name. L05 (não apresentada) × L07 (já apresentada).
    v_emp := pg_temp.f3t_cli('Empresa Legenda Ltda', 'company');
    v_caso2 := pg_temp.f3t_caso(2, 'cliente', v_emp, 'preciso de orçamento de baterias', c_agora - interval '1 hour');
    v_pv := pg_temp.f3t_proposta(v_caso2, v_emp, array['bateria'], 'Baterias');
    v_r := public.retorno_legenda_do_orcamento(v_caso2, v_pv, c_agora);
    perform pg_temp.f3t_igual('5a L05', v_r ->> 'texto',
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento das baterias, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    if v_r -> 'contexto' -> 'nome_permitido' is distinct from 'null'::jsonb then
      raise exception '5b: nome_permitido devia ser nulo';
    end if;
    update public.retorno_previa set pdf_em = c_agora - interval '30 minutes' where id = v_pv;
    v_r := public.retorno_legenda_do_orcamento(v_caso2, v_pv, c_agora);
    perform pg_temp.f3t_igual('5c L07', v_r ->> 'texto',
      'Segue o orçamento das baterias, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    -- L06 × L08: sem nome e sem serviço.
    update public.retorno_previa set pdf_em = null where id = v_pv;
    v_r := public.retorno_legenda_do_orcamento(v_caso2, null, c_agora);
    perform pg_temp.f3t_igual('5d L06', v_r ->> 'texto',
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento que você pediu, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    update public.retorno_previa set pdf_em = c_agora - interval '30 minutes' where id = v_pv;
    v_r := public.retorno_legenda_do_orcamento(v_caso2, null, c_agora);
    perform pg_temp.f3t_igual('5e L08', v_r ->> 'texto',
      'Segue o orçamento que você pediu, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');

    -- ═══ 6. Número novo com cadastro provisório: nome do cadastro, não L05.
    v_cl2 := pg_temp.f3t_cli('Marcos Provisorio Teste');
    v_caso3 := pg_temp.f3t_caso(3, 'numero_novo', null, 'preciso de orçamento de baterias', c_agora - interval '1 hour');
    insert into public.audit_log (table_name, record_id, action, changed_by, new_value, reason)
    values ('clients', v_cl2, 'lead_converted', 'retorno', jsonb_build_object('caso', v_caso3), 'teste');
    v_pv := pg_temp.f3t_proposta(v_caso3, v_cl2, array['bateria'], 'Baterias');
    v_r := public.retorno_legenda_do_orcamento(v_caso3, v_pv, c_agora);
    perform pg_temp.f3t_igual('6 L02 pelo cadastro', v_r ->> 'texto',
      'Oi, Marcos! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento das baterias, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');

    -- ═══ 7. Rascunho: p_client decide o nome e a apresentação, mesmo com outro cliente no caso.
    -- Caso novo, de outro cliente (Rodrigo, já apresentado como cliente), num número que nunca recebeu apresentação:
    -- o v_caso não serve, porque a chave dele já conta como apresentada desde o PDF do passo 4 (4n).
    v_cl3 := pg_temp.f3t_cli('Ana Rascunho Teste');
    v_caso4 := pg_temp.f3t_caso(6, 'cliente', v_cl, 'preciso de orçamento de baterias', c_agora - interval '1 hour');
    v_r := public.retorno_legenda_do_orcamento(v_caso4, null, c_agora, v_cl3);
    perform pg_temp.f3t_igual('7a p_client decide o nome', v_r ->> 'texto',
      'Oi, Ana! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento que você pediu, que vale até segunda (15/03). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.');
    perform pg_temp.f3t_igual('7b nome_permitido', v_r -> 'contexto' ->> 'nome_permitido', 'Ana');

    -- Caso inexistente: 22023.
    begin
      perform public.retorno_legenda_do_orcamento('00000000-0000-4000-8000-000000000000', null, c_agora);
      raise exception '7c: caso inexistente passou' using errcode = 'P0002';
    exception when others then
      if sqlstate <> '22023' then
        raise;
      end if;
    end;

    -- ═══ 8. M07 por _retorno_texto_do_modelo: as quatro aberturas.
    perform pg_temp.f3t_igual('8a corpo', public._retorno_corpo_do_modelo('modelo_ver_no_local', '{}'),
      'para passar o valor certo, o Gustavo precisa ver o serviço no local. Ele combina o melhor dia com você por aqui.');
    perform pg_temp.f3t_igual('8b apos_recibo', public._retorno_abertura_do_modelo('apos_recibo',
        jsonb_build_object('nome', 'Rodrigo', 'corpo', public._retorno_corpo_do_modelo('modelo_ver_no_local', '{}'))),
      'Rodrigo, para passar o valor certo, o Gustavo precisa ver o serviço no local. Ele combina o melhor dia com você por aqui.');
    perform pg_temp.f3t_igual('8c padrao', public._retorno_abertura_do_modelo('padrao',
        jsonb_build_object('nome', 'Rodrigo', 'corpo', public._retorno_corpo_do_modelo('modelo_ver_no_local', '{}'))),
      'Oi, Rodrigo! Para passar o valor certo, o Gustavo precisa ver o serviço no local. Ele combina o melhor dia com você por aqui.');
    perform pg_temp.f3t_igual('8d padrao_apresentacao', public._retorno_abertura_do_modelo('padrao_apresentacao',
        jsonb_build_object('nome', 'Rodrigo', 'corpo', public._retorno_corpo_do_modelo('modelo_ver_no_local', '{}'))),
      c_apr || 'Para passar o valor certo, o Gustavo precisa ver o serviço no local. Ele combina o melhor dia com você por aqui.');
    perform pg_temp.f3t_igual('8e sem_nome', public._retorno_abertura_do_modelo('sem_nome',
        jsonb_build_object('corpo', public._retorno_corpo_do_modelo('modelo_ver_no_local', '{}'))),
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Para passar o valor certo, o Gustavo precisa ver o serviço no local. Ele combina o melhor dia com você por aqui.');
    perform pg_temp.f3t_igual('8f tipo curto', public._retorno_tipo_curto('modelo_ver_no_local'), 'ver no local');

    -- M07 nunca é promovível: fora de retorno_modelo_tipos.
    if exists (select 1 from public.retorno_modelo_tipos t where t.tipo = 'modelo_ver_no_local') then
      raise exception '8g: M07 em retorno_modelo_tipos';
    end if;
    if public._retorno_tipo_sozinho('modelo_ver_no_local', c_agora) then
      raise exception '8h: M07 promovível';
    end if;

    -- ═══ 9. _retorno_aplicar_efeitos: M07 enviado não fecha, grava a marca e cancela as agendadas.
    v_caso4 := pg_temp.f3t_caso(4, 'cliente', v_cl3, 'quanto fica o inversor?', c_agora - interval '3 hours');
    v_saida := pg_temp.f3t_saida(v_caso4, 'adiamento', 'agendada', c_agora + interval '5 hours', 'agendada');
    v_saida2 := pg_temp.f3t_saida(v_caso4, 'modelo_ver_no_local', 'enviando', c_agora, 'm07');
    perform public.retorno_registrar_decisao(v_saida2, 'enviada', '{"provider_message_id": "wa-f3"}', c_agora + interval '1 minute');
    select * into v_ab from public.retorno_aberturas where id = v_caso4;
    -- A hora do efeito é a decidida_em da saída (a reserva do retorno_pegar, c_agora), como na F1
    -- (_retorno_aplicar_efeitos: coalesce(decidida_em, p_agora)), não a hora do registro do envio.
    if v_ab.estado is distinct from 'aberta' or v_ab.visita_a_combinar_em is distinct from c_agora or v_ab.recibo_em is distinct from c_agora
       or v_ab.cumprida_em is not null or v_ab.fechada_em is not null then
      raise exception '9a: caso depois do M07: %', to_jsonb(v_ab);
    end if;
    if (select s.estado || '/' || s.motivo from public.retorno_saidas s where s.id = v_saida) <> 'cancelada/visita_a_combinar' then
      raise exception '9b: agendada não caiu';
    end if;
    -- Regressão: modelo_pronto continua fechando.
    v_saida3 := pg_temp.f3t_saida(pg_temp.f3t_caso(5, 'cliente', v_cl3, 'tá pronto?', c_agora - interval '3 hours'), 'modelo_pronto', 'enviando', c_agora, 'pronto');
    perform public.retorno_registrar_decisao(v_saida3, 'enviada', '{"provider_message_id": "wa-f3b"}', c_agora + interval '1 minute');
    select a.* into v_ab from public.retorno_aberturas a join public.retorno_saidas s on s.abertura_id = a.id where s.id = v_saida3;
    if v_ab.estado is distinct from 'fechada' or v_ab.fechada_motivo is distinct from 'conteudo' or v_ab.visita_a_combinar_em is not null then
      raise exception '9c: modelo_pronto: %', to_jsonb(v_ab);
    end if;

    -- ═══ 10. _retorno_checar_antes: com a marca, adiamento e fim do dia caem; urgente também.
    update public.retorno_aberturas set visita_a_combinar_em = c_agora, estado = 'aberta', cumprida_em = null where id = v_caso4;
    v_r := public._retorno_checar_antes(pg_temp.f3t_saida(v_caso4, 'adiamento', 'agendada', c_agora, 'ad'), c_agora);
    if v_r ->> 'acao' is distinct from 'cancelar' or v_r ->> 'motivo' is distinct from 'visita_a_combinar' then
      raise exception '10a: adiamento (%)', v_r;
    end if;
    v_r := public._retorno_checar_antes(pg_temp.f3t_saida(v_caso4, 'fim_do_dia', 'agendada', c_agora, 'fd'), c_agora);
    if v_r ->> 'acao' is distinct from 'cancelar' or v_r ->> 'motivo' is distinct from 'visita_a_combinar' then
      raise exception '10b: fim do dia (%)', v_r;
    end if;
    v_r := public._retorno_checar_antes(pg_temp.f3t_saida(v_caso4, 'urgente', 'agendada', c_agora, 'urg'), c_agora);
    if v_r ->> 'acao' is distinct from 'cancelar' or v_r ->> 'motivo' is distinct from 'visita_a_combinar' then
      raise exception '10c: urgente (%)', v_r;
    end if;
    -- O recibo de mensagem nova do cliente segue normal: a marca não o cancela.
    v_r := public._retorno_checar_antes(pg_temp.f3t_saida(v_caso4, 'recibo_cliente', 'agendada', c_agora, 'rec'), c_agora);
    if v_r ->> 'motivo' is not distinct from 'visita_a_combinar' then
      raise exception '10d: recibo caiu pela visita (%)', v_r;
    end if;

    -- ═══ 11. retorno_vigia: a marca segura o fechamento automático; resposta com conteúdo fecha mesmo com a marca.
    -- Silêncio: o dono respondeu sem conteúdo às 10:00 de 08/03, ninguém prometeu hora, 5 h depois.
    v_caso := pg_temp.f3t_caso(11, 'cliente', v_cl, 'preciso ver o inversor', '2027-03-08 09:00-03');
    update public.retorno_aberturas set respondida_em = '2027-03-08 10:00-03', visita_a_combinar_em = '2027-03-08 10:00-03' where id = v_caso;
    v_caso2 := pg_temp.f3t_caso(12, 'cliente', v_cl, 'preciso ver o carregador', '2027-03-08 09:00-03');
    update public.retorno_aberturas set respondida_em = '2027-03-08 10:00-03' where id = v_caso2;
    -- Nada: parado há mais de 4 h, com e sem a marca.
    v_caso3 := pg_temp.f3t_caso(13, 'cliente', v_cl, 'a bateria', '2027-03-08 08:00-03');
    -- nivel 'nada' exige motivo (retorno_aberturas_motivo, F1).
    update public.retorno_aberturas set nivel = 'nada', motivo = 'nao_pede_resposta', visita_a_combinar_em = '2027-03-08 09:00-03' where id = v_caso3;
    v_caso4 := pg_temp.f3t_caso(14, 'cliente', v_cl, 'o carregador', '2027-03-08 08:00-03');
    update public.retorno_aberturas set nivel = 'nada', motivo = 'nao_pede_resposta' where id = v_caso4;

    v_vig := public.retorno_vigia(c_t);
    if (v_vig ->> 'ok')::boolean is distinct from true then
      raise exception '11a: vigia com erro: %', v_vig;
    end if;
    select * into v_ab from public.retorno_aberturas where id = v_caso;
    if v_ab.estado = 'fechada' then
      raise exception '11b: com a marca, fechou por silêncio (%)', v_ab.fechada_motivo;
    end if;
    select * into v_ab from public.retorno_aberturas where id = v_caso2;
    if v_ab.estado is distinct from 'fechada' or v_ab.fechada_motivo is distinct from 'silencio' then
      raise exception '11c: sem a marca, devia fechar por silêncio (%/%)', v_ab.estado, v_ab.fechada_motivo;
    end if;
    select * into v_ab from public.retorno_aberturas where id = v_caso3;
    if v_ab.estado = 'fechada' then
      raise exception '11d: com a marca, fechou por nada (%)', v_ab.fechada_motivo;
    end if;
    select * into v_ab from public.retorno_aberturas where id = v_caso4;
    if v_ab.estado is distinct from 'fechada' or v_ab.fechada_motivo is distinct from 'nada' then
      raise exception '11e: sem a marca, devia fechar por nada (%/%)', v_ab.estado, v_ab.fechada_motivo;
    end if;

    -- Expirou: 4 dias úteis sem recebida, com e sem a marca (expira_dias_uteis = 3).
    v_caso2 := pg_temp.f3t_caso(15, 'cliente', v_cl, 'o inversor', '2027-03-01 10:00-03');
    update public.retorno_aberturas set visita_a_combinar_em = '2027-03-02 10:00-03' where id = v_caso2;
    v_caso3 := pg_temp.f3t_caso(16, 'cliente', v_cl, 'a antena', '2027-03-01 10:00-03');
    v_vig := public.retorno_vigia(c_t + interval '1 minute');
    select * into v_ab from public.retorno_aberturas where id = v_caso2;
    if v_ab.estado = 'fechada' then
      raise exception '11f: com a marca, expirou (%)', v_ab.fechada_motivo;
    end if;
    select * into v_ab from public.retorno_aberturas where id = v_caso3;
    if v_ab.estado is distinct from 'fechada' or v_ab.fechada_motivo is distinct from 'expirou' then
      raise exception '11g: sem a marca, devia expirar (%/%)', v_ab.estado, v_ab.fechada_motivo;
    end if;

    -- Regressão do passo 4: resposta com conteúdo fecha o caso com a marca.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at, saida_humana)
    values ('outbound', '5547900900011', 'text', 'Fechado, passa na segunda às oito que eu olho no local.', 'sent', '{"data": {}}'::jsonb,
            c_t + interval '5 minutes', c_t + interval '5 minutes', true);
    v_vig := public.retorno_vigia(c_t + interval '10 minutes');
    select * into v_ab from public.retorno_aberturas where id = v_caso;
    if v_ab.estado is distinct from 'fechada' or v_ab.fechada_motivo is distinct from 'conteudo' or v_ab.cumprida_em is null then
      raise exception '11h: resposta com conteúdo não fechou (%/%)', v_ab.estado, v_ab.fechada_motivo;
    end if;

    raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_desfaz' then
      raise;
    end if;
  end;

  insert into _bancada (arquivo, ok, numeros) values ('retorno_f3_textos', true, '{}');
end
$textos$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
