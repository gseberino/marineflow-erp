-- Retorno F2 (P6): os textos M01 a M06 e T29 a T35, literais, a intenção e o rascunho de orçamento. Roda só pela bancada.
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000097xx; frases inventadas.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f2m_falta(p_sql text) returns text
language plpgsql as $f$
begin
  execute p_sql;
  return 'passou';
exception when others then
  return sqlstate;
end $f$;

do $modelos$
declare
  c_agora constant timestamptz := '2026-11-10 15:00:00-03';
  c_no_bem constant text := 'no seu motorhome';
  v_t text;
  v_cl uuid; v_outro uuid;
  v_msg uuid;
  v_caso uuid;
  v_os uuid;
  v_barco uuid;
  r record;
begin
  begin
    -- M01–M06 e M02b, com cada abertura.
    for r in
      select * from (values
        ('modelo_aguarda_peca', '{"no_bem": "no seu motorhome"}'::jsonb, 'o serviço no seu motorhome está aguardando a chegada de uma peça para seguirmos. O Gustavo te avisa quando ela chegar.'),
        ('modelo_aguarda_peca', '{"no_bem": "no seu motorhome", "te_aviso": true}'::jsonb, 'o serviço no seu motorhome está aguardando a chegada de uma peça para seguirmos. Te aviso por aqui quando ela chegar.'),
        ('modelo_peca_chegou', '{"dia_peca": "09/12"}'::jsonb, 'chegou sim: a peça chegou em 09/12. O próximo passo é o Gustavo marcar o dia do serviço.'),
        ('modelo_peca_chegou', '{"dia_peca": "09/12", "intencao": "status"}'::jsonb, 'a peça do serviço chegou em 09/12. O próximo passo é o Gustavo marcar o dia do serviço.'),
        ('modelo_pronto', '{"no_bem": "no seu motorhome"}'::jsonb, 'ficou sim: o serviço no seu motorhome está pronto. Quando fica bom para você buscar? O Gustavo combina o horário por aqui.'),
        ('modelo_em_servico', '{"no_bem": "no seu motorhome"}'::jsonb, 'o serviço no seu motorhome está em andamento hoje. O Gustavo te passa as novidades por aqui.'),
        ('modelo_liberado', '{}'::jsonb, 'pode sim: o serviço está liberado para retirada. Combine o horário com o Gustavo por aqui.'),
        ('modelo_retirada_nao', '{}'::jsonb, 'ainda não dá para retirar: o serviço não terminou. O Gustavo te chama para combinar.')
      ) as x(tipo, dados, esperado)
    loop
      v_t := public._retorno_corpo_do_modelo(r.tipo, r.dados);
      if v_t is distinct from r.esperado then
        raise exception '1a: % (%)', r.tipo, v_t;
      end if;
      if char_length(public._retorno_abertura_do_modelo('padrao_apresentacao', jsonb_build_object('nome', 'Maximiliano', 'corpo', v_t))) > 400 then
        raise exception '1b: % passou de 400 caracteres', r.tipo;
      end if;
    end loop;
    if pg_temp.f2m_falta($q$select public._retorno_corpo_do_modelo('modelo_pronto', '{}')$q$) <> '22023' then
      raise exception '1c: sem no_bem não falhou';
    end if;
    if pg_temp.f2m_falta($q$select public._retorno_corpo_do_modelo('modelo_peca_chegou', '{"dia_peca": "ontem"}')$q$) <> '22023' then
      raise exception '1d: dia inválido não falhou';
    end if;
    if pg_temp.f2m_falta($q$select public._retorno_corpo_do_modelo('modelo_x', '{}')$q$) <> '22023' then
      raise exception '1e: tipo desconhecido não falhou';
    end if;

    -- As aberturas.
    v_t := public._retorno_corpo_do_modelo('modelo_pronto', jsonb_build_object('no_bem', c_no_bem));
    if public._retorno_abertura_do_modelo('padrao', jsonb_build_object('nome', 'Rodrigo', 'corpo', v_t))
       is distinct from 'Oi, Rodrigo (mensagem automática da HBR). Ficou sim: o serviço no seu motorhome está pronto. Quando fica bom para você buscar? O Gustavo combina o horário por aqui.' then
      raise exception '2a: padrao';
    end if;
    if public._retorno_abertura_do_modelo('padrao_apresentacao', jsonb_build_object('nome', 'Rodrigo', 'corpo', v_t))
       not like 'Oi, Rodrigo! Aqui é o assistente da HBR (mensagem automática). Ficou sim:%' then
      raise exception '2b: apresentacao';
    end if;
    if public._retorno_abertura_do_modelo('sem_nome', jsonb_build_object('corpo', v_t))
       not like 'Oi! Aqui é o assistente da HBR (mensagem automática). Ficou sim:%' then
      raise exception '2c: sem_nome';
    end if;
    if public._retorno_abertura_do_modelo('apos_recibo', jsonb_build_object('nome', 'Rodrigo', 'corpo', v_t))
       not like 'Rodrigo, ficou sim:%' then
      raise exception '2d: apos_recibo';
    end if;
    if public._retorno_abertura_do_modelo('apos_recibo_sem_nome', jsonb_build_object('corpo', v_t)) not like 'Ficou sim:%' then
      raise exception '2e: apos_recibo_sem_nome';
    end if;
    if pg_temp.f2m_falta($q$select public._retorno_abertura_do_modelo('padrao', '{"corpo": "x"}')$q$) <> '22023' then
      raise exception '2f: padrao sem nome não falhou';
    end if;

    -- T29–T35.
    for r in
      select * from (values
        ('recibo_cliente', 'retirada', 'Oi, Rodrigo (mensagem automática da HBR). Recebi. Retirar antes depende de como está o serviço, e quem confirma é o Gustavo: ele te responde hoje até as 19h.'),
        ('recibo_cliente', 'adicional', 'Anotado, Rodrigo (mensagem automática da HBR). Passei ao Gustavo como serviço extra: ele avalia e te passa o valor antes de fazer qualquer coisa. Te responde hoje até as 19h.'),
        ('recibo_cliente', 'vou_confirmar', 'Oi, Rodrigo (mensagem automática da HBR). Vou confirmar com o Gustavo e ele te responde hoje até as 19h.'),
        ('recibo_cliente', 'orcamento', 'Oi, Rodrigo (mensagem automática da HBR). Recebi, e o seu orçamento já está em preparação com o Gustavo; ele te responde hoje até as 19h.'),
        ('adiamento', 'orcamento', 'Rodrigo, seu orçamento está em preparação, e o Gustavo está conferindo os valores. Ele te responde até as 19h.'),
        ('adiamento', 'orcamento_sem_nome', 'Seu orçamento está em preparação, e o Gustavo está conferindo os valores. Ele te responde até as 19h.'),
        ('coleta_numero_novo', 'nome_orcamento', 'Obrigado! Seu orçamento já está em preparação com o Gustavo. Como posso te chamar?')
      ) as x(tipo, variante, esperado)
    loop
      v_t := public._retorno_texto_f2(r.tipo, r.variante, '{"nome": "Rodrigo", "quando": "hoje", "hora": "19h"}');
      if v_t is distinct from r.esperado then
        raise exception '3a: %/% (%)', r.tipo, r.variante, v_t;
      end if;
    end loop;
    if pg_temp.f2m_falta($q$select public._retorno_texto_f2('recibo_cliente', 'retirada', '{"nome": "Rodrigo", "quando": "qualquer dia", "hora": "19h"}')$q$) <> '22023' then
      raise exception '3b: dia inválido não falhou';
    end if;
    if pg_temp.f2m_falta($q$select public._retorno_texto_f2('recibo_cliente', 'padrao', '{}')$q$) <> '22023' then
      raise exception '3c: par da F1 não falhou';
    end if;

    -- A intenção, frase a frase.
    for r in
      select * from (values
        ('como tá o motorhome?', 'status'), ('como está o serviço?', 'status'), ('já ficou pronto?', 'status'), ('tem novidade?', 'status'),
        ('e aí, terminou?', 'status'), ('tem previsão?', 'status'),
        ('a peça chegou?', 'peca'), ('o material já veio?', 'peca'), ('as peças chegaram?', 'peca'),
        ('posso buscar o barco?', 'retirada'), ('dá pra retirar a lancha amanhã?', 'retirada'), ('vou pegar o motorhome', 'retirada'),
        ('quando fica pronto?', 'quando_pronto'), ('qual o prazo?', 'quando_pronto'),
        ('aproveita e olha a bomba', 'adicional'), ('mais um serviço, por favor', 'adicional'),
        ('quanto custa uma bateria?', 'orcamento'), ('preciso trocar o inversor', 'orcamento'),
        ('vou pegar a estrada', null), ('como estamos de agenda', null), ('obrigado', null), ('bom dia', null)
      ) as x(frase, esperada)
    loop
      v_t := public._retorno_intencao_da_frase(public._retorno_busca(r.frase), public._retorno_sinais(r.frase), false);
      if v_t is distinct from r.esperada then
        raise exception '4a: "%" deu %, esperava %', r.frase, v_t, r.esperada;
      end if;
    end loop;
    if public._retorno_intencao_da_frase(public._retorno_busca('posso retirar?'), public._retorno_sinais('posso retirar?'), true) is distinct from 'retirada' then
      raise exception '4b: com libera, o bem é dispensado';
    end if;

    -- O rascunho de orçamento: de 13 dias sim, de 15 não, de outro cliente não, enviado não, do futuro não.
    insert into public.clients (type, name, whatsapp) values ('individual', 'Paulo Modelo Teste', '(47) 90000-9701') returning id into v_cl;
    insert into public.clients (type, name) values ('individual', 'Pedro Modelo Teste') returning id into v_outro;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('inbound', '5547900009701', 'text', 'preciso de um orçamento', 'received', '{"data": {}}'::jsonb, c_agora - interval '1 hour', c_agora - interval '1 hour')
    returning id into v_msg;
    insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                          gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
    values (public._agenda_chave_telefone('5547900009701'), '5547900009701', '47', 'cliente', '{"papel": "cliente"}', v_cl, v_msg, v_msg,
            c_agora - interval '1 hour', c_agora - interval '1 hour', c_agora - interval '1 hour', c_agora - interval '1 hour', 'recibo', 'recibo_cliente', 'aberta', 'sombra')
    returning id into v_caso;
    insert into public.vessels (client_id, name, asset_type) values (v_cl, 'Barco de Teste', 'Lancha') returning id into v_barco;
    insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, grand_total)
    values ('ORÇ-09701', v_cl, v_barco, 'draft', 'draft', 'repair', c_agora - interval '13 days', c_agora - interval '13 days', 100)
    returning id into v_os;
    if not public._retorno_tem_orcamento(v_caso, c_agora) then
      raise exception '5a: rascunho de 13 dias';
    end if;
    update public.service_orders set created_at = c_agora - interval '16 days' where id = v_os;
    if public._retorno_tem_orcamento(v_caso, c_agora) then
      raise exception '5b: rascunho de 16 dias';
    end if;
    update public.service_orders set created_at = c_agora - interval '1 day', client_id = v_outro where id = v_os;
    if public._retorno_tem_orcamento(v_caso, c_agora) then
      raise exception '5c: de outro cliente';
    end if;
    update public.service_orders set client_id = v_cl, quote_status = 'sent' where id = v_os;
    if public._retorno_tem_orcamento(v_caso, c_agora) then
      raise exception '5d: enviado';
    end if;
    update public.service_orders set quote_status = 'draft', created_at = c_agora + interval '1 hour' where id = v_os;
    if public._retorno_tem_orcamento(v_caso, c_agora) then
      raise exception '5e: do futuro';
    end if;

    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f2_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_modelos', true, '{}');
end
$modelos$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
