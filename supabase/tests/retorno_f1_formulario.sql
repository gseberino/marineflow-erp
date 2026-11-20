-- Retorno F1, rr-f1-11 (20/11/2026): o número novo que pede serviço, sem exigir o veículo, recebe o recibo e o formulário de
-- cadastro do dono. Migration 20270214100200. Termina em ROLLBACK, e o bloco se desfaz sozinho.
--   1. _retorno_formulario_lido: o formulário respondido, campo a campo; "Nome: Ana" solto não é formulário.
--   2. _retorno_texto: o T36 é o texto do dono, exato, sem a linha de risco.
--   3. o interruptor de sempre: sem recibo_numero_novo ligado, "quanto fica para instalar uma bateria?" sem o veículo segue sem
--      pedido (byte a byte como hoje); ligado, vira pedido; vendedor nunca.
--   4. retorno_abrir: o recibo agenda o formulário 1 minuto depois, na vaga da coleta.
--   5. retorno_pegar: o formulário espera o recibo; o recibo sai sem pergunta; o formulário sai com o texto exato; recibo
--      cancelado leva o formulário junto.
--   6. a resposta "Nome: …" vira o nome do cadastro provisório, o CPF vira o documento, e os campos ficam na coleta.
--   7. uma vez por contato: o caso seguinte do mesmo número não ganha outro formulário.
-- Relógio em terça 06/01/2026 (antes de qualquer saída real: retorno_pegar pega a mais antiga do banco inteiro, e a premissa
-- confere que nenhuma saída real está devida nesse dia). Telefones 55479000099xx; nomes e números inventados.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f1f_igual(p_rot text, p_valor text, p_esp text) returns void
language plpgsql as $f$
begin
  if p_valor is distinct from p_esp then
    raise exception '%: %, esperava %', p_rot, coalesce(p_valor, '∅'), coalesce(p_esp, '∅');
  end if;
end $f$;

create or replace function pg_temp.f1f_msg(p_fone text, p_corpo text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', p_fone, 'text', p_corpo, 'received', '{"data": {}}'::jsonb, p_em, p_em)
  returning id;
$f$;

create or replace function pg_temp.f1f_abre(p_msg uuid, p_agora timestamptz) returns uuid
language plpgsql as $f$
declare
  v_r jsonb := public.retorno_abrir(p_msg, false, p_agora);
begin
  if v_r -> 'ok' is distinct from 'true'::jsonb or v_r ->> 'abertura_id' is null then
    raise exception 'retorno_abrir não abriu o caso: %', v_r;
  end if;
  return (v_r ->> 'abertura_id')::uuid;
end $f$;

create or replace function pg_temp.f1f_saida(p_caso uuid, p_sufixo text) returns public.retorno_saidas
language sql as $f$
  select s.* from public.retorno_saidas s where s.dedupe_key = 'retorno:' || p_caso || ':' || p_sufixo;
$f$;

do $formulario$
declare
  c_t0 constant timestamptz := '2026-01-06 09:00-03';
  c_form constant text := E'Dados para preenchimento do Orçamento / Ordem de Serviço:\n\nNome:\nCPF:\nData Nasc.:\nCel/Whats:\nEndereço:\nCEP:\nEmail:\nLocal fixo Lancha/Veículo:\nNome (Embarcação):\nFabricante:\nAno:\nModelo:\nTamanho:\nPlaca (Veículo):\n\nÉ muito importante ter o máximo de informações preenchidas.';
  c_pedido constant text := 'boa tarde, quanto fica para instalar uma bateria nova?';
  c_ligados constant text[] := array['recibo_cliente', 'adiamento', 'fim_do_dia', 'urgente', 'acorde'];
  v_r jsonb;
  v_f jsonb;
  v_caso uuid;
  v_caso2 uuid;
  v_rec public.retorno_saidas;
  v_frm public.retorno_saidas;
  v_t timestamptz;
  v_ab public.retorno_aberturas;
begin
  begin
    -- Premissas: nenhuma saída real devida no dia do teste; a configuração do jeito que o teste supõe.
    if exists (select 1 from public.retorno_saidas s where s.estado = 'agendada' and s.enviar_em <= c_t0 + interval '1 day') then
      raise exception '0a: há saída real agendada antes de 07/01/2026: o retorno_pegar do teste a pegaria';
    end if;
    update public.retorno_config
       set modo = 'ligado', tipos_ligados = c_ligados, segura_tudo_ate = null, segura_recibos = false, proximo_envio_em = null
     where id;

    -- ═══ 1. _retorno_formulario_lido.
    v_f := public._retorno_formulario_lido(replace(replace(replace(replace(c_form,
             'Nome:' || E'\n' || 'CPF:', 'Nome: Fulano de Tal Teste' || E'\n' || 'CPF: 111.222.333-44'),
             'Email:', 'Email: fulano@exemplo.invalid'), 'Nome (Embarcação):', 'Nome (Embarcação): Brisa Teste'), 'Ano:', 'Ano: 2019'));
    perform pg_temp.f1f_igual('1a nome', v_f ->> 'nome', 'Fulano de Tal Teste');
    perform pg_temp.f1f_igual('1b cpf só dígitos', v_f ->> 'cpf', '11122233344');
    perform pg_temp.f1f_igual('1c email', v_f ->> 'email', 'fulano@exemplo.invalid');
    perform pg_temp.f1f_igual('1d embarcação não é o nome', v_f ->> 'embarcacao', 'Brisa Teste');
    perform pg_temp.f1f_igual('1e ano', v_f ->> 'ano', '2019');
    perform pg_temp.f1f_igual('1f rótulos', v_f ->> 'rotulos', '14');
    perform pg_temp.f1f_igual('1g campo vazio fica de fora', (v_f ? 'cep')::text, 'false');
    perform pg_temp.f1f_igual('1h formulário vazio: sem nome', (public._retorno_formulario_lido(c_form) ? 'nome')::text, 'false');
    perform pg_temp.f1f_igual('1i "Nome: Ana" solto', public._retorno_formulario_lido('Nome: Ana Teste')::text, null);
    perform pg_temp.f1f_igual('1j negrito do WhatsApp', public._retorno_formulario_lido(E'*Nome:* Ana Teste\n*CPF:* 1\n*CEP:* 2') ->> 'nome', 'Ana Teste');
    perform pg_temp.f1f_igual('1k nome com número sai', (public._retorno_formulario_lido(E'Nome: 4799999\nCPF: 1\nCEP: 2') ? 'nome')::text, 'false');
    perform pg_temp.f1f_igual('1l sem texto', public._retorno_formulario_lido(null)::text, null);

    -- ═══ 2. O T36: o texto do dono, exato, sem a linha de risco.
    perform pg_temp.f1f_igual('2a T36', public._retorno_texto('coleta_numero_novo', 'formulario', '{}'::jsonb), c_form);
    perform pg_temp.f1f_igual('2b sem L01', public._retorno_texto('coleta_numero_novo', 'formulario', '{"risco": "true"}'::jsonb), c_form);
    perform pg_temp.f1f_igual('2c o T18 não mudou', public._retorno_texto('coleta_numero_novo', 'nome', '{}'::jsonb), 'Obrigada! Já passei ao Gustavo. Como posso chamar você?');

    -- ═══ 3. O interruptor de sempre (recibo_numero_novo): desligado, sem o veículo não há pedido.
    perform pg_temp.f1f_msg('5547900009951', c_pedido, c_t0);
    perform pg_temp.f1f_igual('3a desligado', public._retorno_pedido_de_servico('00009951', c_t0, c_t0 + interval '1 minute') ->> 'pedido', 'false');
    v_caso := pg_temp.f1f_abre((select m.id from public.whatsapp_messages m where m.phone_normalized = '5547900009951'), c_t0 + interval '5 seconds');
    select * into v_ab from public.retorno_aberturas a where a.id = v_caso;
    perform pg_temp.f1f_igual('3b caso sem pedido', v_ab.nivel || '/' || coalesce(v_ab.motivo, '∅'), 'nada/numero_novo_sem_pedido');
    perform pg_temp.f1f_igual('3c nenhuma saída', (select count(*)::text from public.retorno_saidas s where s.abertura_id = v_caso), '0');

    update public.retorno_config set tipos_ligados = c_ligados || array['recibo_numero_novo'] where id;
    perform pg_temp.f1f_igual('3d ligado', public._retorno_pedido_de_servico('00009951', c_t0, c_t0 + interval '1 minute') ->> 'pedido', 'true');
    perform pg_temp.f1f_msg('5547900009952', 'vendo baterias com desconto, quanto fica para instalar? sou representante', c_t0);
    perform pg_temp.f1f_igual('3e vendedor nunca', public._retorno_pedido_de_servico('00009952', c_t0, c_t0 + interval '1 minute', 'Representante Baterias') ->> 'pedido', 'false');

    -- ═══ 4. retorno_abrir: recibo e, 1 minuto depois, o formulário, na vaga da coleta.
    v_caso := pg_temp.f1f_abre(pg_temp.f1f_msg('5547900009953', c_pedido, c_t0), c_t0 + interval '5 seconds');
    select * into v_ab from public.retorno_aberturas a where a.id = v_caso;
    perform pg_temp.f1f_igual('4a papel', v_ab.papel, 'numero_novo');
    perform pg_temp.f1f_igual('4b nível', v_ab.nivel, 'recibo');
    v_rec := pg_temp.f1f_saida(v_caso, 'recibo');
    v_frm := pg_temp.f1f_saida(v_caso, 'coleta');
    perform pg_temp.f1f_igual('4c recibo', v_rec.tipo || '/' || v_rec.estado, 'recibo_numero_novo/agendada');
    perform pg_temp.f1f_igual('4d formulário', v_frm.tipo || '/' || v_frm.variante || '/' || v_frm.estado, 'coleta_numero_novo/formulario/agendada');
    perform pg_temp.f1f_igual('4e 1 minuto depois', (v_frm.enviar_em - v_rec.enviar_em)::text, '00:01:00');

    -- ═══ 5. retorno_pegar.
    -- 5a: o formulário devido com o recibo ainda por sair espera o recibo (+1 min); nada mais devido, a chamada não devolve nada.
    update public.retorno_saidas set enviar_em = v_frm.enviar_em + interval '10 minutes' where id = v_rec.id;
    v_r := public.retorno_pegar(v_frm.enviar_em + interval '1 second');
    perform pg_temp.f1f_igual('5a nada devolvido', v_r::text, null);
    perform pg_temp.f1f_igual('5b esperou o recibo', (select (s.enviar_em - (v_frm.enviar_em + interval '10 minutes'))::text from public.retorno_saidas s where s.id = v_frm.id), '00:01:00');
    perform pg_temp.f1f_igual('5c continua agendado', (select s.estado from public.retorno_saidas s where s.id = v_frm.id), 'agendada');
    -- 5d: o recibo sai sem pergunta (o formulário já pede tudo).
    v_t := v_frm.enviar_em + interval '10 minutes' + interval '1 second';
    v_r := public.retorno_pegar(v_t);
    perform pg_temp.f1f_igual('5d o recibo', v_r ->> 'saida_id', v_rec.id::text);
    perform pg_temp.f1f_igual('5e sem pergunta', v_r ->> 'variante', 'sem_pergunta');
    update public.retorno_saidas set estado = 'enviada', enviada_em = v_t, decidida_em = v_t, processando_ate = null where id = v_rec.id;
    -- 5f: o formulário sai com o texto exato, depois do recibo.
    v_r := public.retorno_pegar(v_t + interval '2 minutes');
    perform pg_temp.f1f_igual('5f o formulário', v_r ->> 'saida_id', v_frm.id::text);
    perform pg_temp.f1f_igual('5g variante', v_r ->> 'variante', 'formulario');
    perform pg_temp.f1f_igual('5h texto exato', v_r ->> 'texto', c_form);
    perform pg_temp.f1f_igual('5i trecho do modelo', v_r -> 'validador' -> 'trechos_do_modelo' ->> 0, c_form);
    -- 5j: modo efetivo pelo interruptor de sempre: coleta_numero_novo fora de tipos_ligados = sombra.
    perform pg_temp.f1f_igual('5j em sombra', (select s.modo || '/' || s.estado from public.retorno_saidas s where s.id = v_frm.id), 'sombra/preparada');

    -- ═══ 6. A resposta no formato do formulário: o nome e o CPF vão à coleta e ao cadastro provisório.
    update public.retorno_saidas set estado = 'enviada', enviada_em = v_t + interval '2 minutes', decidida_em = v_t + interval '2 minutes', processando_ate = null
     where id = v_frm.id;
    perform pg_temp.f1f_abre(pg_temp.f1f_msg('5547900009953',
              replace(replace(c_form, 'Nome:' || E'\n' || 'CPF:', 'Nome: Fulano de Tal Teste' || E'\n' || 'CPF: 111.222.333-44'), 'Ano:', 'Ano: 2019'),
              v_t + interval '20 minutes'), v_t + interval '20 minutes 5 seconds');
    select * into v_ab from public.retorno_aberturas a where a.id = v_caso;
    perform pg_temp.f1f_igual('6a nome na coleta', v_ab.coleta ->> 'nome', 'Fulano de Tal Teste');
    perform pg_temp.f1f_igual('6b documento', v_ab.coleta ->> 'documento', '11122233344');
    perform pg_temp.f1f_igual('6c campos literais', v_ab.coleta -> 'formulario' ->> 'ano', '2019');
    perform pg_temp.f1f_igual('6d cadastro provisório agendado', (pg_temp.f1f_saida(v_caso, 'cadastro')).estado, 'agendada');
    perform pg_temp.f1f_igual('6e o que criaria', public.retorno_cadastro_provisorio(v_caso, false) ->> 'nome', 'Fulano de Tal Teste');
    -- A triagem seguinte não apaga o que o formulário trouxe.
    perform public._retorno_triar(v_caso, v_t + interval '30 minutes');
    perform pg_temp.f1f_igual('6f fica', (select a.coleta ->> 'documento' from public.retorno_aberturas a where a.id = v_caso), '11122233344');

    -- ═══ 7. Uma vez por contato: outro caso do mesmo número não ganha outro formulário.
    update public.retorno_aberturas set estado = 'fechada', fechada_em = v_t + interval '1 hour', fechada_motivo = 'conteudo' where id = v_caso;
    v_caso2 := pg_temp.f1f_abre(pg_temp.f1f_msg('5547900009953', 'e para trocar o inversor, quanto fica?', c_t0 + interval '1 day'),
                                c_t0 + interval '1 day 5 seconds');
    if v_caso2 = v_caso then
      raise exception '7a: o caso fechado reabriu';
    end if;
    perform pg_temp.f1f_igual('7b sem outro formulário', (pg_temp.f1f_saida(v_caso2, 'coleta')).variante, null);

    -- ═══ 8. Recibo que não saiu leva o formulário junto, com o mesmo motivo.
    v_caso := pg_temp.f1f_abre(pg_temp.f1f_msg('5547900009954', c_pedido, c_t0 + interval '3 hours'), c_t0 + interval '3 hours 5 seconds');
    v_rec := pg_temp.f1f_saida(v_caso, 'recibo');
    v_frm := pg_temp.f1f_saida(v_caso, 'coleta');
    update public.retorno_saidas set estado = 'recusada', motivo = 'validador', decidida_em = v_rec.enviar_em where id = v_rec.id;
    v_r := public.retorno_pegar(v_frm.enviar_em + interval '1 second');
    perform pg_temp.f1f_igual('8a cancelado com o motivo do recibo', (select s.estado || '/' || s.motivo from public.retorno_saidas s where s.id = v_frm.id), 'cancelada/validador');

    -- ═══ 9. As novas, fechadas ao anônimo e ao painel.
    if has_function_privilege('anon', 'public._retorno_formulario_lido(text)', 'execute')
       or has_function_privilege('authenticated', 'public._retorno_formulario_lido(text)', 'execute')
       or has_function_privilege('anon', 'public._retorno_numero_novo_ligado()', 'execute')
       or has_function_privilege('anon', 'public.retorno_pegar(timestamptz)', 'execute') then
      raise exception '9a: função aberta ao anon ou ao authenticated';
    end if;

    raise exception 'retorno_f1_formulario_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f1_formulario_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f1_formulario', true, '{}');
end
$formulario$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
