-- Retorno F2 (P7A): a lista. Relógio fixo em ter 10/11/2026 (antes de qualquer caso real). Roda só pela bancada.
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000093xx; a frase marcada é inventada.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.retorno_f2_lis_caso(p_fone text, p_papel text, p_aberta timestamptz, p_client uuid default null,
                                                       p_body text default 'FRASE-MARCADA-F2 preciso de uma ajuda com a lancha',
                                                       p_tipo text default 'text', p_nivel text default 'recibo')
returns uuid
language plpgsql as $f$
declare
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', p_fone, p_tipo, p_body, 'received', '{"data": {}}'::jsonb, p_aberta, p_aberta)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
  values (public._agenda_chave_telefone(p_fone), p_fone, '47', p_papel, jsonb_build_object('papel', p_papel), p_client, v_msg, v_msg,
          p_aberta, p_aberta, p_aberta, p_aberta, p_nivel, 'recibo_cliente', 'aberta', 'sombra')
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta)
  values (v_msg, v_id, public._agenda_chave_telefone(p_fone), p_aberta, p_aberta, 'x', true);
  return v_id;
end $f$;

do $lista$
declare
  c_agora constant timestamptz := '2026-11-10 15:00:00-03';   -- terça
  v_dono uuid;
  v_r jsonb;
  v_vivo jsonb;
  v_t text;
  v_cl uuid; v_cl2 uuid;
  v_novo uuid; v_vencido uuid; v_passa uuid; v_prom uuid; v_prom2 uuid; v_resto uuid; v_fora uuid;
  v_ses uuid; v_pend uuid; v_cartao uuid;
  v_n integer;
  v_ordem uuid[];
begin
  begin
    select d.id into v_dono from public._comprovante_dono() d;
    update public.retorno_config set modo = 'sombra', tipos_ligados = '{}', cartao_max_itens = 3;

    -- Vazio.
    v_r := public.retorno_cartao_abrir('puxar', c_agora);
    if v_r ->> 'acao' is distinct from 'vazio' or v_r ->> 'texto' is distinct from 'Ninguém esperando agora.' then
      raise exception '1: vazio (%)', v_r;
    end if;
    if public.retorno_cartao_vivo(c_agora) is not null then
      raise exception '1b: há cartão sem caso';
    end if;

    -- A ordem: venceu, passagem, pedido novo, promessa (a mais próxima primeiro), o resto.
    insert into public.clients (type, name, whatsapp) values ('individual', 'Rodrigo Lista Teste', '(47) 90000-9301') returning id into v_cl;
    insert into public.clients (type, name, whatsapp) values ('individual', 'Paulo Lista Teste', '(47) 90000-9302') returning id into v_cl2;
    v_resto := pg_temp.retorno_f2_lis_caso('5547900009306', 'cliente', c_agora - interval '6 hours', v_cl);
    v_prom2 := pg_temp.retorno_f2_lis_caso('5547900009305', 'cliente', c_agora - interval '5 hours', v_cl);
    v_prom := pg_temp.retorno_f2_lis_caso('5547900009304', 'cliente', c_agora - interval '4 hours', v_cl);
    v_novo := pg_temp.retorno_f2_lis_caso('5547900009303', 'numero_novo', c_agora - interval '3 hours');
    v_passa := pg_temp.retorno_f2_lis_caso('5547900009302', 'cliente', c_agora - interval '2 hours', v_cl2, p_nivel => 'passagem');
    v_vencido := pg_temp.retorno_f2_lis_caso('5547900009301', 'cliente', c_agora - interval '1 hour', v_cl);
    update public.retorno_aberturas set estado = 'vencida' where id = v_vencido;
    update public.retorno_aberturas set prometido_ate = c_agora + interval '4 hours' where id = v_prom;
    update public.retorno_aberturas set prometido_ate = c_agora + interval '20 hours' where id = v_prom2;
    -- quem nunca entra: fornecedor, parceiro, nível nada, cumprido; e o caso do futuro
    v_fora := pg_temp.retorno_f2_lis_caso('5547900009307', 'fornecedor', c_agora - interval '1 hour');
    v_fora := pg_temp.retorno_f2_lis_caso('5547900009308', 'cliente_parceiro', c_agora - interval '1 hour');
    v_fora := pg_temp.retorno_f2_lis_caso('5547900009309', 'contato_conhecido', c_agora - interval '1 hour');
    v_fora := pg_temp.retorno_f2_lis_caso('5547900009310', 'cliente', c_agora - interval '1 hour', v_cl);
    update public.retorno_aberturas set cumprida_em = c_agora - interval '10 minutes', cumprida_por = 'celular' where id = v_fora;
    v_fora := pg_temp.retorno_f2_lis_caso('5547900009311', 'cliente', c_agora + interval '1 hour', v_cl);

    select array_agg(c.abertura_id) into v_ordem from public._retorno_cartao_casos(c_agora, null) c;
    if v_ordem is distinct from array[v_vencido, v_passa, v_novo, v_prom, v_prom2, v_resto] then
      raise exception '2: ordem errada (%)', v_ordem;
    end if;

    -- A lista com 3 casos e "e mais 3". Só depois da mensagem de uma lista o texto é exato.
    update public.retorno_mensagens set recebida_em = recebida_em where abertura_id = v_vencido;
    v_r := public.retorno_dito('{"comando": "retorno"}', v_dono, c_agora);
    v_t := 'Retorno · 6 esperando' || E'\n'
        || '1. Rodrigo · 14:00 · sem promessa · ''FRASE-MARCADA-F2 preciso de uma ajuda com a lancha''' || E'\n'
        || '2. Paulo · 13:00 · sem promessa · ''FRASE-MARCADA-F2 preciso de uma ajuda com a lancha''' || E'\n'
        || '3. número novo · 12:00 · sem promessa · ''FRASE-MARCADA-F2 preciso de uma ajuda com a lancha''' || E'\n'
        || 'e mais 3: *retorno*' || E'\n'
        || '*ver 1* · *resolvido 1* · *pessoal 1*';
    if v_r ->> 'texto' is distinct from v_t then
      raise exception '3a: texto (%)', v_r ->> 'texto';
    end if;
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    if (select c.estado from public.retorno_cartoes c where c.id = v_cartao) is distinct from 'lista'
       or (select c.pendencia_id from public.retorno_cartoes c where c.id = v_cartao) is not null then
      raise exception '3b: a lista não pode ter pendência';
    end if;
    if not v_r -> 'historico' ->> 'assistant' like '%1 = Rodrigo, 2 = Paulo, 3 = número novo%' then
      raise exception '3c: o historico não leva os rótulos (%)', v_r -> 'historico';
    end if;
    if (v_r -> 'historico')::text like '%FRASE-MARCADA%' then
      raise exception '3d: o historico levou o texto do cliente';
    end if;

    -- O 2º *retorno* mostra os mesmos casos: item de lista não bloqueia.
    v_r := public.retorno_dito('{"comando": "retorno"}', v_dono, c_agora + interval '1 minute');
    if v_r ->> 'texto' is distinct from v_t then
      raise exception '4: o 2º retorno mudou (%)', v_r ->> 'texto';
    end if;
    v_cartao := (v_r ->> 'cartao_id')::uuid;

    -- retorno_cartao_vivo: a lista mais recente, e nada depois de 24 h.
    v_vivo := public.retorno_cartao_vivo(c_agora + interval '2 minutes');
    if (v_vivo ->> 'id')::uuid is distinct from v_cartao or v_vivo ->> 'estado' is distinct from 'lista'
       or jsonb_array_length(v_vivo -> 'itens') <> 3 or v_vivo -> 'letras' -> '1' is distinct from '[]'::jsonb then
      raise exception '5a: cartão vivo (%)', v_vivo;
    end if;
    if public.retorno_cartao_vivo(c_agora + interval '25 hours') is not null then
      raise exception '5b: lista com mais de 24 h';
    end if;

    -- ver 2: as recebidas e o que se sabe, com a frase ao dono e fora do historico.
    v_r := public.retorno_dito('{"comando": "ver", "n": 2}', v_dono, c_agora + interval '2 minutes');
    if v_r ->> 'texto' is distinct from 'Paulo · sem promessa' || E'\n' || '13:00 ''FRASE-MARCADA-F2 preciso de uma ajuda com a lancha''' then
      raise exception '6a: ver (%)', v_r ->> 'texto';
    end if;
    if v_r -> 'historico' is distinct from '{"user": "(ver 2)", "assistant": "(mostrei o caso 2 ao dono)"}'::jsonb then
      raise exception '6b: historico do ver (%)', v_r -> 'historico';
    end if;
    v_r := public.retorno_dito('{"comando": "ver", "n": 3}', v_dono, c_agora + interval '30 hours');
    if v_r ->> 'texto' is distinct from 'Não há lista aberta. Mande *retorno*.' then
      raise exception '6c: ver sem lista (%)', v_r;
    end if;

    -- pessoal 2 tira o item, e o texto se regrava sem renumerar.
    v_r := public.retorno_dito('{"comando": "pessoal", "n": 2}', v_dono, c_agora + interval '3 minutes');
    if v_r ->> 'texto' not like 'Paulo: anotado como pessoal.%' then
      raise exception '7a: pessoal (%)', v_r;
    end if;
    v_t := (select c.texto from public.retorno_cartoes c where c.id = v_cartao);
    if v_t like '%Paulo%' or v_t not like 'Retorno · 5 esperando%' or v_t not like '%3. número novo%' then
      raise exception '7b: texto regravado (%)', v_t;
    end if;
    v_r := public.retorno_dito('{"comando": "ver", "n": 2}', v_dono, c_agora + interval '4 minutes');
    if v_r ->> 'texto' is distinct from 'Não há caso 2 nesta lista. Mande *retorno*.' then
      raise exception '7c: ver do item que saiu (%)', v_r;
    end if;

    -- Cartão vivo com pendência: approved não é órfão; rejected fecha.
    insert into public.ai_operator_sessions (channel, status) values ('whatsapp', 'open') returning id into v_ses;
    insert into public.ai_operator_pending_actions (session_id, action_name, risk_level, title, summary, payload, status, expires_at)
    values (v_ses, 'retorno_executar_cartao', 'high', 'Cartão do retorno', 'Cartão do retorno', '{}', 'pending', c_agora + interval '1 day')
    returning id into v_pend;
    insert into public.retorno_cartoes (gatilho, dia, estado, pendencia_id, hash, texto, criado_em, enviado_em, expira_em)
    values ('puxar', '2026-11-10', 'vivo', v_pend, 'h', 'cartão', c_agora, c_agora, c_agora + interval '1 day')
    returning id into v_cartao;
    insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, hash, opcoes)
    values (v_cartao, 1, v_vencido, 'peca_sem_registro', 'i',
            '[{"letra": "B", "rotulo": "chegou"}, {"letra": "C", "rotulo": "previsão"}]');
    update public.ai_operator_pending_actions set status = 'approved', approved_at = c_agora where id = v_pend;
    v_vivo := public.retorno_cartao_vivo(c_agora + interval '5 minutes');
    if (v_vivo ->> 'id')::uuid is distinct from v_cartao or v_vivo ->> 'estado' is distinct from 'vivo' then
      raise exception '8a: approved fechou o cartão (%)', v_vivo;
    end if;
    if v_vivo -> 'letras' -> '1' is distinct from '["B", "C"]'::jsonb then
      raise exception '8b: letras (%)', v_vivo -> 'letras';
    end if;
    update public.ai_operator_pending_actions set status = 'failed' where id = v_pend;
    v_vivo := public.retorno_cartao_vivo(c_agora + interval '6 minutes');
    if (select c.estado from public.retorno_cartoes c where c.id = v_cartao) is distinct from 'decidido'
       or (select i.estado from public.retorno_cartao_itens i where i.cartao_id = v_cartao) is distinct from 'fora' then
      raise exception '8c: órfão não fechou';
    end if;
    if (v_vivo ->> 'id')::uuid = v_cartao then
      raise exception '8d: devolveu o cartão fechado';
    end if;

    -- Os trechos: corte na palavra, quebra de linha, áudio, foto, documento.
    if public._retorno_trecho(E'linha um\n\nlinha  dois', 'text', false, 140) is distinct from '''linha um linha dois''' then
      raise exception '9a: quebra de linha';
    end if;
    v_t := public._retorno_trecho(repeat('palavra ', 40), 'text', false, 140);
    if char_length(v_t) > 143 or v_t not like '%palavra…''' then
      raise exception '9b: corte (%)', v_t;
    end if;
    if public._retorno_trecho('[audio]', 'audio', true, 140) is distinct from '(áudio ainda sem transcrição)'
       or public._retorno_trecho('', 'image', false, 140) is distinct from '(foto)'
       or public._retorno_trecho('[documento]', 'document', false, 140) is distinct from '(documento)' then
      raise exception '9c: mídia';
    end if;

    -- O prazo: "prometi" só com a promessa ouvida.
    if public._retorno_prazo_curto(v_prom, c_agora) is distinct from 'sem promessa' then
      raise exception '10a: promessa sem recibo enviado';
    end if;
    insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, modo, estado, decidida_em, enviada_em, enviar_em, texto, dedupe_key)
    values (v_prom, 'recibo_cliente', public._agenda_chave_telefone('5547900009304'), '5547900009304', 'ligado', 'enviada',
            c_agora - interval '1 hour', c_agora - interval '1 hour', c_agora - interval '1 hour', 'Recebi sua mensagem.', 'teste-f2-lis:1');
    if public._retorno_prazo_curto(v_prom, c_agora) is distinct from 'prometi até 19h' then
      raise exception '10b: mesmo dia (%)', public._retorno_prazo_curto(v_prom, c_agora);
    end if;
    update public.retorno_aberturas set prometido_ate = '2026-11-11 10:00-03' where id = v_prom;
    if public._retorno_prazo_curto(v_prom, c_agora) is distinct from 'prometi até amanhã 10h' then
      raise exception '10c: amanhã';
    end if;
    update public.retorno_aberturas set prometido_ate = '2026-11-16 10:00-03' where id = v_prom;
    if public._retorno_prazo_curto(v_prom, c_agora) is distinct from 'prometi até seg 10h' then
      raise exception '10d: outro dia';
    end if;
    update public.retorno_aberturas set prometido_ate = '2026-11-09 19:00-03' where id = v_prom;
    if public._retorno_prazo_curto(v_prom, c_agora) is distinct from 'venceu ontem' then
      raise exception '10e: venceu';
    end if;

    -- Nada do que o cliente escreveu foi parar na conversa do assistente.
    select count(*) into v_n from public.ai_operator_messages m where m.content like '%FRASE-MARCADA-F2%';
    if v_n <> 0 then
      raise exception '11: % linhas com a frase marcada em ai_operator_messages', v_n;
    end if;

    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f2_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_lista', true, '{}');
end
$lista$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
