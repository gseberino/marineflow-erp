-- Retorno F5 (P6): o aceite por texto e os dados da nota. O léxico (as barreiras no texto cru, a contraproposta sem "R$" e
-- as formas fortes), a detecção (com e sem caso, candidatos no instante da mensagem, a agenda na ordem de produção, a sombra
-- antes da agenda, o áudio pela chave aceite_audio, o papel pelo telefone inteiro, o caso só com o mesmo telefone dele; o
-- registro e os dados da nota conferem o telefone do mesmo jeito), a marca d'água (a 1ª vez, a folga de 10 minutos, a
-- mensagem gravada tarde, o áudio transcrito depois), o que falta para a nota (os mesmos casos do Vitest), o documento e o
-- CEP lidos, a letra A/C, o registro com o "Fechado" e o pedido de dados, os dados gravados só no vazio, o dia do envio,
-- dois aceites do mesmo cliente e o vigia medindo a sombra com a cadência desligada. Roda só pela bancada (grupo 8,
-- F5_ONDA=3, F5_TESTES=retorno_f5_aceite). Termina em ROLLBACK; cada cenário roda no seu sub-bloco, que se desfaz sozinho
-- (raise 'f5a_cenario'). Só confere as próprias linhas sintéticas: telefones inventados 55479000099xx (a chave sai do
-- telefone: 000099xx), nomes inventados (Ana, João, Pedro), documentos inventados (ORÇ-993xx, OS-993xx; CPF e CNPJ gerados
-- com dígito válido), usuário de teste @teste.invalid. Nenhuma mensagem real é lida; as frases são inventadas. Relógio: ter
-- 12/01/2027 (Brasília) nas linhas gravadas à mão; nos cenários que passam pelo retorno_abrir (que grava processada_em =
-- now()) e pela agenda, o relógio é o now() da transação.
-- Os casos de _orcamento_faltas_para_nota ($faltas$) e de _orcamento_documento_lido ($documentos$) são os mesmos que
-- src/lib/ficha-cliente-paridade.test.ts lê deste arquivo: o TS confere o mesmo esperado.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f5a_cli(p_nome text, p_fone text, p_phone text default null) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp, phone) values ('individual', p_nome, p_fone, p_phone) returning id
$f$;

create or replace function pg_temp.f5a_orc(p_cliente uuid, p_numero text, p_em timestamptz, p_status text default 'draft',
                                           p_quote text default 'draft') returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, quote_validity_days)
  values (p_numero, p_cliente, v_v, p_status, p_quote, 'repair', p_em - interval '2 days', p_em - interval '2 days', 100, 7)
  returning id into v_id;
  return v_id;
end $f$;

-- Um envio ao cliente (a chave de p_fone) em orcamento_envios.
create or replace function pg_temp.f5a_envio(p_os uuid, p_fone text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, marcou)
  select so.id, so.client_id, 'tela', public._agenda_chave_telefone(p_fone), true, p_em, false
    from public.service_orders so where so.id = p_os
  returning id
$f$;

-- O orçamento enviado ao cliente pela tela: o funil em sent, a hora, a chave, a validade e a linha do envio.
create or replace function pg_temp.f5a_enviado(p_cliente uuid, p_fone text, p_numero text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v_os uuid;
begin
  v_os := pg_temp.f5a_orc(p_cliente, p_numero, p_em);
  update public.service_orders
     set quote_status = 'sent', orcamento_enviado_em = p_em, orcamento_enviado_via = 'tela',
         orcamento_enviado_chave = public._agenda_chave_telefone(p_fone),
         quote_validity_date = (p_em at time zone 'America/Sao_Paulo')::date + 7
   where id = v_os;
  perform pg_temp.f5a_envio(v_os, p_fone, p_em);
  return v_os;
end $f$;

-- Uma mensagem inventada do cliente, com a hora real igual à de gravação.
create or replace function pg_temp.f5a_msg(p_fone text, p_corpo text, p_em timestamptz, p_tipo text default 'text') returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real,
                                        occurred_at)
  values ('inbound', p_fone, p_tipo, p_corpo, 'received', '{"data": {}}'::jsonb, p_em, p_em)
  returning id
$f$;

-- A mensagem como o retorno_abrir a grava, com a hora de processamento escolhida.
create or replace function pg_temp.f5a_rm(p_fone text, p_corpo text, p_em timestamptz, p_proc timestamptz, p_tipo text default 'text',
                                          p_abertura uuid default null, p_consumida boolean default false,
                                          p_ao_dono boolean default false, p_audio boolean default false) returns uuid
language plpgsql as $f$
declare
  v_id uuid;
begin
  v_id := pg_temp.f5a_msg(p_fone, p_corpo, p_em, p_tipo);
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, sinais,
                                        pede_resposta, pede_motivo, audio_pendente, consumida, agenda_ao_dono, processada_em)
  values (v_id, p_abertura, public._agenda_chave_telefone(p_fone), p_em, p_em, md5(coalesce(p_corpo, '')), '{}'::jsonb, false, null,
          p_audio, p_consumida, p_ao_dono, p_proc);
  return v_id;
end $f$;

create or replace function pg_temp.f5a_ac(p_msg uuid) returns public.orcamento_aceites
language sql as $f$
  select a from public.orcamento_aceites a where a.whatsapp_message_id = p_msg
$f$;

-- Um aceite gravado à mão (o que a detecção gravaria), para os testes da letra, do registro e dos dados.
create or replace function pg_temp.f5a_aceite(p_msg uuid, p_cliente uuid, p_chave text, p_os uuid, p_estado text default 'detectado',
                                              p_total numeric default 100) returns uuid
language sql as $f$
  insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado,
                                        total_visto)
  values (p_msg, p_cliente, p_chave, (case when p_os is null then '{}'::uuid[] else array[p_os] end), p_os, 'pode fazer', p_estado,
          p_total)
  returning id
$f$;

-- As saídas do aceite em texto: "tipo:modo:estado", na ordem do tipo.
create or replace function pg_temp.f5a_saidas(p_aceite uuid) returns text
language sql as $f$
  select coalesce(string_agg(s.tipo || ':' || s.modo || ':' || s.estado, ',' order by s.tipo), '')
    from public.retorno_saidas s where s.emissor = 'orcamento' and s.dados ->> 'aceite_id' = p_aceite::text
$f$;

create or replace function pg_temp.f5a_marca(p_em timestamptz) returns void
language sql as $f$
  update public.retorno_config set orcamento_aceite_ate = p_em where id
$f$;

do $aceite$
declare
  c_t constant timestamptz := '2027-01-12 10:00-03';        -- ter: os orçamentos saem às 10:00
  c_dono constant uuid := 'b1600000-0000-4000-8000-0000000099a1';
  c_novas constant text[] := array['_orcamento_aceite', '_orcamento_candidatos', '_orcamento_agenda_esperando',
                                   '_orcamento_cartao_aceites', '_orcamento_aceites_detectar', '_orcamento_faltas_para_nota',
                                   '_orcamento_documento_lido', '_orcamento_cep_lido', '_orcamento_dados_detectar',
                                   'orcamento_aceite_com_sinal', 'orcamento_aceite_registrar', 'orcamento_dados_gravar',
                                   '_orcamento_aceite_fechar_antigos', '_orcamento_cliente_do_telefone'];
  c_publicas constant text[] := array['orcamento_aceite_com_sinal', 'orcamento_aceite_registrar', 'orcamento_dados_gravar'];
  -- Os casos de faltasParaNota (os de src/lib/ficha-cliente.test.ts e as bordas do trim e dos dígitos). O Vitest
  -- ficha-cliente-paridade.test.ts lê este mesmo literal e confere o esperado no TS.
  c_faltas constant jsonb := $faltas$[
    {"nome": "cadastro completo", "cliente": {"cpf_cnpj": "123.456.789-00", "address_line_1": "Rua A, 10", "neighborhood": "Centro", "city": "Itajaí", "state": "SC", "postal_code": "88300-000", "ie_indicator": 9, "state_registration": null}, "esperado": []},
    {"nome": "lista o que o servidor recusaria", "cliente": {"cpf_cnpj": null, "address_line_1": "Rua A, 10", "neighborhood": "", "city": "Itajaí", "state": "SC", "postal_code": null, "ie_indicator": 9, "state_registration": null}, "esperado": ["CPF/CNPJ", "bairro", "CEP"]},
    {"nome": "documento e CEP pela metade", "cliente": {"cpf_cnpj": "123.456", "address_line_1": "Rua A, 10", "neighborhood": "Centro", "city": "Itajaí", "state": "SC", "postal_code": "8830", "ie_indicator": 9, "state_registration": null}, "esperado": ["CPF/CNPJ incompleto", "CEP incompleto"]},
    {"nome": "contribuinte do ICMS sem IE", "cliente": {"cpf_cnpj": "123.456.789-00", "address_line_1": "Rua A, 10", "neighborhood": "Centro", "city": "Itajaí", "state": "SC", "postal_code": "88300-000", "ie_indicator": 1, "state_registration": null}, "esperado": ["inscrição estadual"]},
    {"nome": "contribuinte do ICMS com IE", "cliente": {"cpf_cnpj": "123.456.789-00", "address_line_1": "Rua A, 10", "neighborhood": "Centro", "city": "Itajaí", "state": "SC", "postal_code": "88300-000", "ie_indicator": 1, "state_registration": "123.456.789"}, "esperado": []},
    {"nome": "cadastro vazio", "cliente": {"cpf_cnpj": null, "address_line_1": null, "neighborhood": null, "city": null, "state": null, "postal_code": null, "ie_indicator": null, "state_registration": null}, "esperado": ["CPF/CNPJ", "rua", "bairro", "cidade", "UF", "CEP"]},
    {"nome": "só espaços, tabulação e quebra de linha", "cliente": {"cpf_cnpj": "123.456.789-00", "address_line_1": "   ", "neighborhood": "\t", "city": " \n ", "state": " ", "postal_code": "88300-000", "ie_indicator": 9, "state_registration": null}, "esperado": ["rua", "bairro", "cidade", "UF"]},
    {"nome": "espaço que não quebra", "cliente": {"cpf_cnpj": "123.456.789-00", "address_line_1": "Rua A, 10", "neighborhood": "Centro", "city": " ", "state": "SC", "postal_code": "88300-000", "ie_indicator": 9, "state_registration": null}, "esperado": ["cidade"]},
    {"nome": "CNPJ completo", "cliente": {"cpf_cnpj": "47.391.826/0001-92", "address_line_1": "Rua A, 10", "neighborhood": "Centro", "city": "Itajaí", "state": "SC", "postal_code": "88300-000", "ie_indicator": 9, "state_registration": null}, "esperado": []},
    {"nome": "documento com 12 dígitos", "cliente": {"cpf_cnpj": "123456789012", "address_line_1": "Rua A, 10", "neighborhood": "Centro", "city": "Itajaí", "state": "SC", "postal_code": "88300-000", "ie_indicator": 9, "state_registration": null}, "esperado": ["CPF/CNPJ incompleto"]},
    {"nome": "CEP com 9 dígitos", "cliente": {"cpf_cnpj": "123.456.789-00", "address_line_1": "Rua A, 10", "neighborhood": "Centro", "city": "Itajaí", "state": "SC", "postal_code": "88300-0001", "ie_indicator": 9, "state_registration": null}, "esperado": ["CEP incompleto"]},
    {"nome": "CEP só com letras", "cliente": {"cpf_cnpj": "123.456.789-00", "address_line_1": "Rua A, 10", "neighborhood": "Centro", "city": "Itajaí", "state": "SC", "postal_code": "sem CEP", "ie_indicator": 9, "state_registration": null}, "esperado": ["CEP"]},
    {"nome": "IE só com letras", "cliente": {"cpf_cnpj": "123.456.789-00", "address_line_1": "Rua A, 10", "neighborhood": "Centro", "city": "Itajaí", "state": "SC", "postal_code": "88300-000", "ie_indicator": 1, "state_registration": "ISENTO"}, "esperado": ["inscrição estadual"]},
    {"nome": "IE fora do contribuinte", "cliente": {"cpf_cnpj": "123.456.789-00", "address_line_1": "Rua A, 10", "neighborhood": "Centro", "city": "Itajaí", "state": "SC", "postal_code": "88300-000", "ie_indicator": 2, "state_registration": null}, "esperado": []},
    {"nome": "tudo faltando com IE", "cliente": {"cpf_cnpj": null, "address_line_1": null, "neighborhood": null, "city": null, "state": null, "postal_code": null, "ie_indicator": 1, "state_registration": null}, "esperado": ["CPF/CNPJ", "inscrição estadual", "rua", "bairro", "cidade", "UF", "CEP"]}
  ]$faltas$;
  -- Os documentos lidos da resposta do cliente (CPF e CNPJ gerados com dígito válido; nenhum é de pessoa real conferida).
  c_documentos constant jsonb := $documentos$[
    {"texto": "Meu CPF é 390.533.447-05", "esperado": "39053344705"},
    {"texto": "cpf 71582016437 e cep 88330-000", "esperado": "71582016437"},
    {"texto": "CNPJ 47.391.826/0001-92", "esperado": "47391826000192"},
    {"texto": "pode ligar no (47) 99904-1234, CPF 264.983.017-40", "esperado": "26498301740"},
    {"texto": "CPF 390.533.447-06", "esperado": null},
    {"texto": "meu telefone é 47999041234", "esperado": null},
    {"texto": "CPF 111.111.111-11", "esperado": null},
    {"texto": "CEP 88330-000", "esperado": null}
  ]$documentos$;
  v_x jsonb;
  v_rec record;
  v_r jsonb;
  v text;
  v_n integer;
  v_i integer := 0;
  v_id uuid;
  v_ana uuid; v_joao uuid; v_pedro uuid; v_c uuid;
  v_os uuid; v_os2 uuid; v_os3 uuid;
  v_m uuid; v_m2 uuid; v_m3 uuid;
  v_a uuid; v_a2 uuid;
  v_ab uuid;
  v_ac public.orcamento_aceites;
  v_s public.retorno_saidas;
  v_agora timestamptz := now();
  v_n_fun integer := 0;
begin
  begin
  -- A configuração de cada rodada: o retorno em sombra (o retorno_abrir roda), a cadência desligada, o aceite no cartão.
  update public.retorno_config
     set modo = 'sombra', orcamento_modo = 'desligado', aceite_modo = 'cartao', aceite_audio = false, dados_nota_ligado = false,
         aceite_janela = interval '30 days', dados_nota_janela = interval '7 days', orcamento_aceite_ate = null,
         envio_mao_modo = 'desligado'
   where id;
  insert into public.app_users (id, full_name, email, role, active)
  values (c_dono, 'TESTE F5 aceite dono', 'teste-f5-aceite-dono@teste.invalid', 'admin', true);

  -- ── 1. O léxico, com frases inventadas ──
  for v_rec in
    select * from (values
      ('Pode fazer.', true, null, 'pode fazer'), ('pode seguir', true, null, 'pode seguir'), ('Fechado!', true, null, 'fechado'),
      ('aprovado', true, null, 'aprovado'), ('pode fazer sim', true, null, 'pode fazer'), ('vamos fazer', true, null, 'vamos fazer'),
      ('autorizo', true, null, 'autorizo'),
      ('pode fazer?', false, 'pergunta', null), ('se fizer por 4 mil eu fecho', false, 'condicional', null),
      ('fechado, mas consegue um desconto?', false, 'pergunta', null), ('ainda não, vou pensar', false, 'negacao', null),
      ('fechei com outra empresa', false, 'encerrou', null), ('PARAR', false, 'parar', null), ('ok', false, null, null),
      ('sim', false, null, null), ('beleza', false, null, null), ('pode ser', false, null, null), ('obrigado', false, null, null),
      ('[audio]', false, null, null), ('pode fazer o orçamento da bateria', false, 'pedido_de_orcamento', null),
      ('consegue me mandar um orçamento', false, 'pedido_de_orcamento', null),
      -- A contraproposta sem "R$" (revisão das ondas 1 a 3): número solto, "k", "%", valor por extenso, "se for", a metade.
      ('Fecho em 4500', false, 'negociacao', null), ('fechado em 4k', false, 'negociacao', null),
      ('Pode fazer por quatro mil', false, 'negociacao', null), ('Fechado, 4.500 à vista', false, 'negociacao', null),
      ('Se for 4000 pode fazer', false, 'condicional', null), ('pode fazer pela metade', false, 'negociacao', null),
      ('fecho com 10% a menos', false, 'negociacao', null), ('fecho com dez por cento a menos', false, 'negociacao', null),
      ('pode fazer, menos a pintura', false, 'negociacao', null), ('fecho por quinhentos', false, 'negociacao', null),
      ('se ficar em quatro e quinhentos eu fecho', false, 'condicional', null), ('pode fazer se sair por cem', false, 'condicional', null),
      -- E o aceite de verdade continua aceite.
      ('Pode fazer, obrigado!', true, null, 'pode fazer'), ('Pode seguir com o serviço', true, null, 'pode seguir'),
      ('de acordo', true, null, 'de acordo'), ('Bom dia! Aprovado', true, null, 'aprovado'), ('pode começar', true, null, 'pode comecar')
    ) as x(texto, aceite, barrado, sinal)
  loop
    v_r := public._orcamento_aceite(v_rec.texto);
    if (v_r ->> 'aceite')::boolean is distinct from v_rec.aceite or v_r ->> 'barrado' is distinct from v_rec.barrado
       or v_r ->> 'sinal' is distinct from v_rec.sinal then
      raise exception '1: "%" deu %', v_rec.texto, v_r;
    end if;
  end loop;

  -- ── 2. Um caso por barreira, com a forma forte junto ──
  for v_rec in
    select * from (values
      ('pode fazer?', 'pergunta'), ('Pode fazer, fica R$ 4.000', 'valor'), ('PARAR', 'parar'),
      ('desisti do orçamento, pode fechar', 'encerrou'), ('pode fazer, mas se baixar eu fecho', 'condicional'),
      ('pode fazer com desconto à vista', 'negociacao'), ('pode fazer por 4000', 'negociacao'),
      ('pode fazer, mas não agora', 'negacao'), ('podem fazer o orçamento da bateria', 'pedido_de_orcamento')
    ) as x(texto, barrado)
  loop
    v_r := public._orcamento_aceite(v_rec.texto);
    if (v_r ->> 'aceite')::boolean is not false or v_r ->> 'barrado' is distinct from v_rec.barrado then
      raise exception '2: "%" deu % (esperava %)', v_rec.texto, v_r, v_rec.barrado;
    end if;
  end loop;

  -- ── 17. As barreiras no texto cru (o _retorno_busca tira o "?" e o "$") ──
  if public._retorno_busca('Pode fazer?') is distinct from 'pode fazer' then
    raise exception '17a: _retorno_busca mudou (a barreira do "?" no cru deixou de ser necessária?)';
  end if;
  for v_rec in
    select * from (values ('Pode fazer?', 'pergunta'), ('fechado?', 'pergunta'), ('Fechado! R$ 4 mil, ok?', 'pergunta'),
                          ('Fechado, R$ 4.000', 'valor')) as x(texto, barrado)
  loop
    v_r := public._orcamento_aceite(v_rec.texto);
    if (v_r ->> 'aceite')::boolean is not false or v_r ->> 'barrado' is distinct from v_rec.barrado then
      raise exception '17b: "%" deu %', v_rec.texto, v_r;
    end if;
  end loop;
  if (public._orcamento_aceite('Fechado!') ->> 'aceite')::boolean is not true then
    raise exception '17c: "Fechado!" não deu aceite';
  end if;

  -- ── 3. Detecção: 1 orçamento enviado e "Pode fazer." → detectado, com o id da mensagem e o total ──
  begin
    v_ana := pg_temp.f5a_cli('Ana Aceite F5 Teste', '5547900009931');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009931', 'ORÇ-99331', c_t);
    perform pg_temp.f5a_marca(c_t + interval '4 hours');
    v_m := pg_temp.f5a_rm('5547900009931', 'Pode fazer.', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes 1 second');
    v_n := public._orcamento_aceites_detectar(c_t + interval '4 hours 10 minutes');
    v_ac := pg_temp.f5a_ac(v_m);
    if v_n is distinct from 1 or v_ac.id is null or v_ac.estado is distinct from 'detectado' or v_ac.service_order_id is distinct from v_os
       or v_ac.total_visto is distinct from 100::numeric or v_ac.candidatos is distinct from array[v_os]
       or v_ac.sinal_lido is distinct from 'pode fazer' or v_ac.abertura_id is not null or v_ac.client_id is distinct from v_ana
       or v_ac.chave is distinct from '00009931'
       or v_ac.faltas_nota is distinct from array['CPF/CNPJ', 'rua', 'bairro', 'cidade', 'UF', 'CEP'] then
      raise exception '3a: detectado (% gravados: %)', v_n, to_jsonb(v_ac);
    end if;
    -- A marca vai ao maior processada_em lido, nunca a p_agora.
    if (select c.orcamento_aceite_ate from public.retorno_config c where c.id) is distinct from c_t + interval '4 hours 5 minutes 1 second' then
      raise exception '3b: a marca não foi ao maior lido';
    end if;
    -- O texto do cliente não foi gravado.
    if row_to_json(v_ac)::text ~* 'pode fazer\.' then
      raise exception '3c: o texto do cliente foi gravado';
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 3b. "Fechado!" sem caso (o retorno_abrir grava a mensagem com abertura nula), e "Fechado, obrigado" num caso vivo de
  --        nível nada, que continua na lista depois que o caso fecha ──
  begin
    v_ana := pg_temp.f5a_cli('Ana Fechado F5 Teste', '5547900009932');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009932', 'ORÇ-99332', v_agora - interval '3 hours');
    perform pg_temp.f5a_marca(v_agora - interval '5 minutes');
    v_m := pg_temp.f5a_msg('5547900009932', 'Fechado!', v_agora - interval '1 hour');
    v_r := public.retorno_abrir(v_m, false, v_agora);
    if (select rm.abertura_id from public.retorno_mensagens rm where rm.whatsapp_message_id = v_m) is not null
       or not exists (select 1 from public.retorno_mensagens rm where rm.whatsapp_message_id = v_m) then
      raise exception '3d: "Fechado!" sem caso não ficou com abertura nula (%)', v_r;
    end if;
    perform public._orcamento_aceites_detectar(v_agora + interval '1 minute');
    v_ac := pg_temp.f5a_ac(v_m);
    if v_ac.estado is distinct from 'detectado' or v_ac.abertura_id is not null
       or not exists (select 1 from public._orcamento_cartao_aceites(v_agora + interval '1 minute') l
                       where l.aceite_id = v_ac.id and l.tipo_item = 'aceite' and l.abertura_id is null) then
      raise exception '3e: "Fechado!" sem caso (%)', to_jsonb(v_ac);
    end if;
    -- Outro cliente, com um caso vivo de nível nada (a agenda consumiu a 1ª mensagem).
    v_joao := pg_temp.f5a_cli('João Fechado F5 Teste', '5547900009933');
    v_os2 := pg_temp.f5a_enviado(v_joao, '5547900009933', 'ORÇ-99333', v_agora - interval '3 hours');
    v_m2 := pg_temp.f5a_msg('5547900009933', 'A peça já chegou?', v_agora - interval '2 hours');
    v_r := public.retorno_abrir(v_m2, true, v_agora);
    v_ab := (v_r ->> 'abertura_id')::uuid;
    if v_ab is null or v_r ->> 'nivel' is distinct from 'nada' then
      raise exception '3f: o caso de nível nada não abriu (%)', v_r;
    end if;
    v_m3 := pg_temp.f5a_msg('5547900009933', 'Fechado, obrigado', v_agora - interval '90 minutes');
    perform public.retorno_abrir(v_m3, false, v_agora);
    if (select rm.abertura_id from public.retorno_mensagens rm where rm.whatsapp_message_id = v_m3) is distinct from v_ab then
      raise exception '3g: "Fechado, obrigado" não entrou no caso vivo';
    end if;
    perform public._orcamento_aceites_detectar(v_agora + interval '2 minutes');
    v_ac := pg_temp.f5a_ac(v_m3);
    if v_ac.estado is distinct from 'detectado' or v_ac.abertura_id is distinct from v_ab or v_ac.service_order_id is distinct from v_os2 then
      raise exception '3h: "Fechado, obrigado" com caso (%)', to_jsonb(v_ac);
    end if;
    -- 4 h depois o vigia da F1 fecha o caso (nível nada): o aceite continua na lista.
    update public.retorno_aberturas set estado = 'fechada', fechada_em = v_agora + interval '4 hours', fechada_motivo = 'nada'
     where id = v_ab;
    if not exists (select 1 from public._orcamento_cartao_aceites(v_agora + interval '4 hours 1 minute') l
                    where l.aceite_id = v_ac.id and l.abertura_id = v_ab) then
      raise exception '3i: o aceite saiu da lista quando o caso fechou';
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 4. 2 orçamentos → duvida; nenhum → nada; enviado há 31 dias → nada; o PDF depois da mensagem → nada ──
  begin
    perform pg_temp.f5a_marca(c_t + interval '4 hours');
    v_ana := pg_temp.f5a_cli('Ana Dúvida F5 Teste', '5547900009934');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009934', 'ORÇ-99334', c_t);
    v_os2 := pg_temp.f5a_enviado(v_ana, '5547900009934', 'ORÇ-99335', c_t + interval '1 hour');
    v_m := pg_temp.f5a_rm('5547900009934', 'Pode fazer.', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes');
    v_joao := pg_temp.f5a_cli('João Sem Orçamento F5 Teste', '5547900009935');
    v_m2 := pg_temp.f5a_rm('5547900009935', 'Pode fazer.', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes');
    v_pedro := pg_temp.f5a_cli('Pedro Antigo F5 Teste', '5547900009936');
    v_os3 := pg_temp.f5a_enviado(v_pedro, '5547900009936', 'ORÇ-99336', c_t - interval '31 days');
    v_m3 := pg_temp.f5a_rm('5547900009936', 'Pode fazer.', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes');
    v_c := pg_temp.f5a_cli('Ana Depois F5 Teste', '5547900009937');
    v_id := pg_temp.f5a_rm('5547900009937', 'Pode fazer.', c_t + interval '4 hours', c_t + interval '4 hours 5 minutes');
    perform pg_temp.f5a_enviado(v_c, '5547900009937', 'ORÇ-99337', c_t + interval '4 hours 3 minutes');
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 10 minutes');
    v_ac := pg_temp.f5a_ac(v_m);
    if v_ac.estado is distinct from 'duvida' or v_ac.service_order_id is not null
       or v_ac.candidatos is distinct from array[v_os, v_os2] then
      raise exception '4a: 2 orçamentos (%)', to_jsonb(v_ac);
    end if;
    if (pg_temp.f5a_ac(v_m2)).id is not null or (pg_temp.f5a_ac(v_m3)).id is not null or (pg_temp.f5a_ac(v_id)).id is not null then
      raise exception '4b: nenhum candidato, envio há 31 dias ou PDF depois da mensagem gravou aceite';
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 5. A agenda. Na ordem de produção: agenda_resposta_do_cliente com "Pode marcar." (grava a resposta e marca a
  --        mensagem da agenda respondida) e só depois o retorno_abrir → agenda, com a OS da agenda ──
  begin
    update public.agenda_config set modo_cliente = 'ligado' where id;
    v_ana := pg_temp.f5a_cli('Ana Agenda F5 Teste', '5547900009938');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009938', 'ORÇ-99338', v_agora - interval '1 day');
    v_os2 := pg_temp.f5a_orc(v_ana, 'OS-99339', v_agora - interval '3 days', 'scheduled', 'approved');
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, base, enviar_em, valida_ate,
                                                 aprovacao, estado, dedupe_key, enviada_em)
    values (v_ana, v_os2, 'vespera', 'rodada', 'ligado', 'Oi, Ana! Amanhã é o dia do serviço. Tudo certo por aí?', '{}'::jsonb,
            v_agora - interval '11 hours', v_agora + interval '1 day', 'livre', 'enviada', 'teste-f5-aceite-agenda-' || v_ana,
            v_agora - interval '11 hours');
    perform pg_temp.f5a_marca(v_agora - interval '5 minutes');
    v_m := pg_temp.f5a_msg('5547900009938', 'Pode marcar.', v_agora - interval '1 hour');
    begin
      v_r := public.agenda_resposta_do_cliente('5547900009938', 'Pode marcar.', v_m, 'text', 'acordo', null,
                                               v_agora - interval '1 hour' + interval '5 seconds');
    exception when others then
      raise exception '5a: agenda_resposta_do_cliente falhou: %', sqlerrm;
    end;
    if not exists (select 1 from public.agenda_cliente_respostas r where r.whatsapp_message_id = v_m and r.modo = 'ligado') then
      raise exception '5b: a agenda não gravou a resposta (%)', v_r;
    end if;
    perform public.retorno_abrir(v_m, false, v_agora);
    perform public._orcamento_aceites_detectar(v_agora + interval '1 minute');
    v_ac := pg_temp.f5a_ac(v_m);
    if v_ac.estado is distinct from 'agenda' or v_ac.resultado ->> 'os_agenda' is distinct from 'OS-99339' then
      raise exception '5c: na ordem de produção (%)', to_jsonb(v_ac);
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;
  -- A mensagem da agenda enviada há 10 h e sem resposta → agenda; a mensagem consumida → agenda.
  begin
    perform pg_temp.f5a_marca(c_t + interval '4 hours');
    v_ana := pg_temp.f5a_cli('Ana Agenda Espera F5 Teste', '5547900009939');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009939', 'ORÇ-99340', c_t);
    v_os2 := pg_temp.f5a_orc(v_ana, 'OS-99341', c_t - interval '3 days', 'scheduled', 'approved');
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, base, enviar_em, valida_ate,
                                                 aprovacao, estado, dedupe_key, enviada_em)
    values (v_ana, v_os2, 'vespera', 'rodada', 'ligado', 'Oi, Ana! Amanhã é o dia do serviço. Tudo certo por aí?', '{}'::jsonb,
            c_t - interval '6 hours', c_t + interval '1 day', 'livre', 'enviada', 'teste-f5-aceite-espera-' || v_ana,
            c_t - interval '6 hours');
    v_m := pg_temp.f5a_rm('5547900009939', 'Pode fazer.', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes');
    v_joao := pg_temp.f5a_cli('João Consumida F5 Teste', '5547900009940');
    v_os3 := pg_temp.f5a_enviado(v_joao, '5547900009940', 'ORÇ-99342', c_t);
    v_m2 := pg_temp.f5a_rm('5547900009940', 'Pode fazer.', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes',
                           'text', null, true);
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 10 minutes');
    if (pg_temp.f5a_ac(v_m)).estado is distinct from 'agenda' or (pg_temp.f5a_ac(v_m)).resultado ->> 'os_agenda' is distinct from 'OS-99341' then
      raise exception '5d: a agenda esperando há 10 h (%)', to_jsonb(pg_temp.f5a_ac(v_m));
    end if;
    if (pg_temp.f5a_ac(v_m2)).estado is distinct from 'agenda' then
      raise exception '5e: a mensagem consumida (%)', to_jsonb(pg_temp.f5a_ac(v_m2));
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 6. Sombra (antes da agenda, com resultado.seria); desligado; o áudio pela chave ──
  begin
    update public.retorno_config set aceite_modo = 'sombra' where id;
    perform pg_temp.f5a_marca(c_t + interval '4 hours');
    v_ana := pg_temp.f5a_cli('Ana Sombra F5 Teste', '5547900009941');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009941', 'ORÇ-99343', c_t);
    v_m := pg_temp.f5a_rm('5547900009941', 'Pode fazer.', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes');
    v_joao := pg_temp.f5a_cli('João Sombra F5 Teste', '5547900009942');
    v_os2 := pg_temp.f5a_enviado(v_joao, '5547900009942', 'ORÇ-99344', c_t);
    v_m2 := pg_temp.f5a_rm('5547900009942', 'Fechado!', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes',
                           'text', null, true);
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 10 minutes');
    v_ac := pg_temp.f5a_ac(v_m);
    if v_ac.estado is distinct from 'sombra' or v_ac.resultado ->> 'seria' is distinct from 'detectado'
       or v_ac.service_order_id is distinct from v_os or v_ac.total_visto is distinct from 100::numeric then
      raise exception '6a: sombra com 1 candidato (%)', to_jsonb(v_ac);
    end if;
    v_ac := pg_temp.f5a_ac(v_m2);
    if v_ac.estado is distinct from 'sombra' or v_ac.resultado ->> 'seria' is distinct from 'agenda' then
      raise exception '6b: sombra com a mensagem consumida (%)', to_jsonb(v_ac);
    end if;
    if exists (select 1 from public._orcamento_cartao_aceites(c_t + interval '4 hours 10 minutes')) then
      raise exception '6c: a lista do cartão não está vazia na sombra';
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;
  begin
    update public.retorno_config set aceite_modo = 'desligado' where id;
    perform pg_temp.f5a_marca(c_t + interval '4 hours');
    v_ana := pg_temp.f5a_cli('Ana Desligado F5 Teste', '5547900009943');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009943', 'ORÇ-99345', c_t);
    v_m := pg_temp.f5a_rm('5547900009943', 'Pode fazer.', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes');
    v_n := public._orcamento_aceites_detectar(c_t + interval '4 hours 10 minutes');
    if v_n is distinct from 0 or (pg_temp.f5a_ac(v_m)).id is not null
       or (select c.orcamento_aceite_ate from public.retorno_config c where c.id) is distinct from c_t + interval '4 hours 10 minutes' then
      raise exception '6d: desligado gravou ou não só avançou a marca';
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;
  begin
    perform pg_temp.f5a_marca(c_t + interval '4 hours');
    v_ana := pg_temp.f5a_cli('Ana Áudio F5 Teste', '5547900009944');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009944', 'ORÇ-99346', c_t);
    v_m := pg_temp.f5a_rm('5547900009944', 'pode fazer', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes', 'audio');
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 10 minutes');
    if (pg_temp.f5a_ac(v_m)).id is not null then
      raise exception '6e: o áudio entrou com aceite_audio falso';
    end if;
    update public.retorno_config set aceite_audio = true where id;
    perform pg_temp.f5a_marca(c_t + interval '4 hours');
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 11 minutes');
    if (pg_temp.f5a_ac(v_m)).estado is distinct from 'detectado' then
      raise exception '6f: o áudio transcrito não entrou com aceite_audio (%)', to_jsonb(pg_temp.f5a_ac(v_m));
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 7. O número com 2 cadastros: o caso ambíguo, e quem_escreve sem caso → nada ──
  begin
    perform pg_temp.f5a_marca(c_t + interval '4 hours');
    v_ana := pg_temp.f5a_cli('Ana Ambígua F5 Teste', '5547900009945');
    v_joao := pg_temp.f5a_cli('João Ambíguo F5 Teste', '5547900009945');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009945', 'ORÇ-99347', c_t);
    v_m := pg_temp.f5a_msg('5547900009945', 'Bom dia', c_t + interval '3 hours');
    insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, clientes, primeira_msg_id, ultima_msg_id, aberta_em,
                                          gravada_em, ultima_em, ultima_gravada_em, nivel, modo)
    values ('00009945', '5547900009945', 'cliente_ambiguo', '{}'::jsonb, array[v_ana, v_joao], v_m, v_m, c_t + interval '3 hours',
            c_t + interval '3 hours', c_t + interval '3 hours', c_t + interval '3 hours', 'recibo', 'sombra')
    returning id into v_ab;
    v_m2 := pg_temp.f5a_rm('5547900009945', 'Pode fazer.', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes',
                           'text', v_ab);
    v_m3 := pg_temp.f5a_rm('5547900009945', 'Fechado!', c_t + interval '4 hours 6 minutes', c_t + interval '4 hours 6 minutes');
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 10 minutes');
    if (pg_temp.f5a_ac(v_m2)).id is not null or (pg_temp.f5a_ac(v_m3)).id is not null then
      raise exception '7: o número com 2 cadastros gravou aceite';
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 8. A marca d'água: a 1ª vez só avança; mais de 10 min antes da marca nunca entra; a transação lenta entra pela folga;
  --        a linha relida não grava de novo. 8b: a mensagem gravada tarde. 8c: o áudio transcrito depois ──
  begin
    update public.retorno_config set orcamento_aceite_ate = null where id;
    v_ana := pg_temp.f5a_cli('Ana Marca F5 Teste', '5547900009946');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009946', 'ORÇ-99348', c_t);
    v_m := pg_temp.f5a_rm('5547900009946', 'Pode fazer.', c_t + interval '3 hours 40 minutes', c_t + interval '3 hours 40 minutes');
    v_n := public._orcamento_aceites_detectar(c_t + interval '4 hours');
    if v_n is distinct from 0 or (pg_temp.f5a_ac(v_m)).id is not null
       or (select c.orcamento_aceite_ate from public.retorno_config c where c.id) is distinct from c_t + interval '4 hours' then
      raise exception '8a: a 1ª vez não só avançou a marca';
    end if;
    v_m2 := pg_temp.f5a_rm('5547900009946', 'Fechado!', c_t + interval '4 hours 10 minutes', c_t + interval '4 hours 10 minutes');
    v_n := public._orcamento_aceites_detectar(c_t + interval '4 hours 10 minutes 30 seconds');
    if v_n is distinct from 1 or (pg_temp.f5a_ac(v_m2)).id is null or (pg_temp.f5a_ac(v_m)).id is not null
       or (select c.orcamento_aceite_ate from public.retorno_config c where c.id) is distinct from c_t + interval '4 hours 10 minutes' then
      raise exception '8b: a linha das 14:10 (% gravados)', v_n;
    end if;
    -- A transação que começou às 14:07 e confirmou às 14:11: processada_em = 14:07, visível só agora.
    v_m3 := pg_temp.f5a_rm('5547900009946', 'Pode seguir', c_t + interval '4 hours 7 minutes', c_t + interval '4 hours 7 minutes');
    v_n := public._orcamento_aceites_detectar(c_t + interval '4 hours 15 minutes');
    if v_n is distinct from 1 or (pg_temp.f5a_ac(v_m3)).id is null
       or (select c.orcamento_aceite_ate from public.retorno_config c where c.id) is distinct from c_t + interval '4 hours 10 minutes' then
      raise exception '8c: a transação lenta (% gravados)', v_n;
    end if;
    v_n := public._orcamento_aceites_detectar(c_t + interval '4 hours 16 minutes');
    if v_n is distinct from 0
       or (select count(*) from public.orcamento_aceites a where a.client_id = v_ana) is distinct from 2::bigint then
      raise exception '8d: a linha relida gravou de novo (% gravados)', v_n;
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;
  begin
    -- 8b. Recebida às 14:00 e processada às 14:20, com a marca às 14:10: entra na rodada das 14:25, com os candidatos das
    --     14:00 (o orçamento que saiu às 14:05 não é candidato).
    perform pg_temp.f5a_marca(c_t + interval '4 hours 10 minutes');
    v_ana := pg_temp.f5a_cli('Ana Tarde F5 Teste', '5547900009947');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009947', 'ORÇ-99349', c_t);
    v_os2 := pg_temp.f5a_enviado(v_ana, '5547900009947', 'ORÇ-99350', c_t + interval '4 hours 5 minutes');
    v_m := pg_temp.f5a_rm('5547900009947', 'Pode fazer.', c_t + interval '4 hours', c_t + interval '4 hours 20 minutes');
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 25 minutes');
    v_ac := pg_temp.f5a_ac(v_m);
    if v_ac.estado is distinct from 'detectado' or v_ac.service_order_id is distinct from v_os or v_ac.candidatos is distinct from array[v_os] then
      raise exception '8e: a mensagem gravada tarde (%)', to_jsonb(v_ac);
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;
  begin
    -- 8c. O áudio às 14:00, sem transcrição ([audio], audio_pendente): nada. Às 14:30 a transcrição chega (a reavaliação
    --     regrava processada_em e o corpo vira "pode fazer"): detectado. Com aceite_audio falso, nada nas duas vezes.
    update public.retorno_config set aceite_audio = true where id;
    perform pg_temp.f5a_marca(c_t + interval '3 hours 55 minutes');
    v_ana := pg_temp.f5a_cli('Ana Transcrição F5 Teste', '5547900009948');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009948', 'ORÇ-99351', c_t);
    v_m := pg_temp.f5a_rm('5547900009948', '[audio]', c_t + interval '4 hours', c_t + interval '4 hours', 'audio', null, false, false, true);
    v_joao := pg_temp.f5a_cli('João Transcrição F5 Teste', '5547900009949');
    v_os2 := pg_temp.f5a_enviado(v_joao, '5547900009949', 'ORÇ-99352', c_t);
    v_m2 := pg_temp.f5a_rm('5547900009949', '[audio]', c_t + interval '4 hours', c_t + interval '4 hours', 'audio', null, false, false, true);
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 5 minutes');
    if (pg_temp.f5a_ac(v_m)).id is not null then
      raise exception '8f: o áudio sem transcrição gravou aceite';
    end if;
    update public.whatsapp_messages set body = 'pode fazer' where id in (v_m, v_m2);
    update public.retorno_mensagens set processada_em = c_t + interval '4 hours 30 minutes', audio_pendente = false, corpo_hash = md5('pode fazer')
     where whatsapp_message_id in (v_m, v_m2);
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 35 minutes');
    if (pg_temp.f5a_ac(v_m)).estado is distinct from 'detectado' then
      raise exception '8g: o áudio transcrito depois (%)', to_jsonb(pg_temp.f5a_ac(v_m));
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;
  begin
    update public.retorno_config set aceite_audio = false where id;
    perform pg_temp.f5a_marca(c_t + interval '3 hours 55 minutes');
    v_ana := pg_temp.f5a_cli('Ana Sem Áudio F5 Teste', '5547900009950');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009950', 'ORÇ-99353', c_t);
    v_m := pg_temp.f5a_rm('5547900009950', '[audio]', c_t + interval '4 hours', c_t + interval '4 hours', 'audio', null, false, false, true);
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 5 minutes');
    update public.whatsapp_messages set body = 'pode fazer' where id = v_m;
    update public.retorno_mensagens set processada_em = c_t + interval '4 hours 30 minutes', audio_pendente = false, corpo_hash = md5('pode fazer')
     where whatsapp_message_id = v_m;
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 35 minutes');
    if (pg_temp.f5a_ac(v_m)).id is not null then
      raise exception '8h: o áudio entrou com aceite_audio falso';
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 9. _orcamento_faltas_para_nota: os mesmos casos e o mesmo esperado do TS ──
  for v_x in select e from jsonb_array_elements(c_faltas) e loop
    v_i := v_i + 1;
    insert into public.clients (type, name, cpf_cnpj, address_line_1, neighborhood, city, state, postal_code, ie_indicator,
                                state_registration)
    values ('individual', 'Ana Paridade F5 Teste ' || v_i, v_x -> 'cliente' ->> 'cpf_cnpj', v_x -> 'cliente' ->> 'address_line_1',
            v_x -> 'cliente' ->> 'neighborhood', v_x -> 'cliente' ->> 'city', v_x -> 'cliente' ->> 'state',
            v_x -> 'cliente' ->> 'postal_code', (v_x -> 'cliente' ->> 'ie_indicator')::integer,
            v_x -> 'cliente' ->> 'state_registration')
    returning id into v_id;
    if public._orcamento_faltas_para_nota(v_id) is distinct from array(select jsonb_array_elements_text(v_x -> 'esperado')) then
      raise exception '9: "%" deu % (o TS dá %)', v_x ->> 'nome', public._orcamento_faltas_para_nota(v_id), v_x -> 'esperado';
    end if;
  end loop;
  if v_i < 12 then
    raise exception '9b: só % casos de faltas', v_i;
  end if;

  -- ── 10. O documento lido (o dígito verificador de masks.ts) e o CEP ──
  for v_x in select e from jsonb_array_elements(c_documentos) e loop
    if public._orcamento_documento_lido(v_x ->> 'texto') is distinct from v_x ->> 'esperado' then
      raise exception '10a: "%" deu %', v_x ->> 'texto', public._orcamento_documento_lido(v_x ->> 'texto');
    end if;
  end loop;
  for v_rec in
    select * from (values ('CEP 88330-000', '88330000'), ('cep: 88.330-000', '88330000'), ('meu cep é 88330000', '88330000'),
                          ('88330-000 (cep)', '88330000'), ('88330-000', null), ('telefone 47999041234', null),
                          ('cep 8833-000', null)) as x(texto, esperado)
  loop
    if public._orcamento_cep_lido(v_rec.texto) is distinct from v_rec.esperado then
      raise exception '10b: "%" deu %', v_rec.texto, public._orcamento_cep_lido(v_rec.texto);
    end if;
  end loop;

  -- ── 11. A letra A/C: sent → awaiting_deposit, com audit_log e o id da mensagem; total mudado e já convertido: recusa ──
  begin
    v_ana := pg_temp.f5a_cli('Ana Sinal F5 Teste', '5547900009951');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009951', 'ORÇ-99354', c_t);
    v_m := pg_temp.f5a_msg('5547900009951', 'Pode fazer.', c_t + interval '4 hours');
    v_a := pg_temp.f5a_aceite(v_m, v_ana, '00009951', v_os);
    v_r := public.orcamento_aceite_com_sinal(v_a, c_dono, c_t + interval '5 hours');
    if v_r is distinct from jsonb_build_object('ok', true, 'numero', 'ORÇ-99354', 'quote_status', 'awaiting_deposit')
       or (select so.quote_status from public.service_orders so where so.id = v_os) is distinct from 'awaiting_deposit'
       or (select so.converted_to_os_at from public.service_orders so where so.id = v_os) is not null
       or not exists (select 1 from public.audit_log l where l.table_name = 'service_orders' and l.record_id = v_os
                                                       and l.changed_by = c_dono::text and strpos(l.reason, v_m::text) > 0
                                                       and l.new_value ->> 'quote_status' = 'awaiting_deposit') then
      raise exception '11a: com sinal (%)', v_r;
    end if;
    v_os2 := pg_temp.f5a_enviado(v_ana, '5547900009951', 'ORÇ-99355', c_t);
    v_m2 := pg_temp.f5a_msg('5547900009951', 'Fechado!', c_t + interval '4 hours 1 minute');
    v_a2 := pg_temp.f5a_aceite(v_m2, v_ana, '00009951', v_os2);
    update public.service_orders set grand_total = 200 where id = v_os2;
    v_r := public.orcamento_aceite_com_sinal(v_a2, c_dono, c_t + interval '5 hours');
    if v_r is distinct from '{"ok": false, "motivo": "orcamento_mudou"}'::jsonb
       or (select so.quote_status from public.service_orders so where so.id = v_os2) is distinct from 'sent' then
      raise exception '11b: o total mudou (%)', v_r;
    end if;
    v_os3 := pg_temp.f5a_enviado(v_ana, '5547900009951', 'ORÇ-99356', c_t);
    v_m3 := pg_temp.f5a_msg('5547900009951', 'Aprovado', c_t + interval '4 hours 2 minutes');
    v_id := pg_temp.f5a_aceite(v_m3, v_ana, '00009951', v_os3);
    update public.service_orders set status = 'open', converted_to_os_at = c_t + interval '4 hours 30 minutes',
                                     service_order_number = 'OS-99356', quote_status = 'approved'
     where id = v_os3;
    v_r := public.orcamento_aceite_com_sinal(v_id, c_dono, c_t + interval '5 hours');
    if (v_r ->> 'ok')::boolean is not false or v_r ->> 'motivo' is distinct from 'orcamento_mudou' then
      raise exception '11c: já convertido (%)', v_r;
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 12. O registro: o "Fechado" com todas as colunas (telefone da mensagem, não do cadastro), em sombra; os dados com
  --        faltas; p_ok falso; adiado; a pré-condição (um "Fechado" só) ──
  begin
    update public.retorno_config set dados_nota_ligado = true where id;
    -- O cadastro tem o WhatsApp 0001…52 e o telefone 0001…53; ela escreveu do 53.
    v_ana := pg_temp.f5a_cli('Ana Registro F5 Teste', '5547900009952', '5547900009953');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009953', 'ORÇ-99357', c_t);
    v_m := pg_temp.f5a_msg('5547900009953', 'Pode fazer.', c_t + interval '4 hours');
    v_a := pg_temp.f5a_aceite(v_m, v_ana, '00009953', v_os);
    v_r := public.orcamento_aceite_registrar(v_a, true, '{"escolha": "com_sinal", "numero": "ORÇ-99357"}'::jsonb, c_dono, true,
                                             c_t + interval '5 hours');
    if v_r is distinct from '{"ok": true, "fechado": "sombra", "dados": true}'::jsonb then
      raise exception '12a: registrar (%)', v_r;
    end if;
    v_ac := pg_temp.f5a_ac(v_m);
    if v_ac.estado is distinct from 'com_sinal' or v_ac.decidido_por is distinct from c_dono
       or v_ac.decidido_em is distinct from c_t + interval '5 hours' or v_ac.pedir_dados is not true
       or v_ac.resultado ->> 'escolha' is distinct from 'com_sinal' then
      raise exception '12b: o aceite registrado (%)', to_jsonb(v_ac);
    end if;
    select * into v_s from public.retorno_saidas s where s.dedupe_key = 'orcamento:aceite:' || v_a || ':fechado:sombra';
    if v_s.id is null or v_s.emissor is distinct from 'orcamento' or v_s.tipo is distinct from 'orc_fechado'
       or v_s.origem is distinct from 'retorno_orcamento' or v_s.classe is distinct from 'resposta_imediata'
       or v_s.chave is distinct from '00009953' or v_s.phone_normalized is distinct from '5547900009953'
       or v_s.client_id is distinct from v_ana or v_s.modo is distinct from 'sombra' or v_s.estado is distinct from 'agendada'
       or v_s.enviar_em is distinct from c_t + interval '5 hours' or v_s.abertura_id is not null
       or v_s.dados ->> 'aceite_id' is distinct from v_a::text or v_s.dados ->> 'os_id' is distinct from v_os::text
       or v_s.dados ->> 'dia_envio' is distinct from '12/01' then
      raise exception '12c: a saída do "Fechado" (%)', to_jsonb(v_s);
    end if;
    select * into v_s from public.retorno_saidas s where s.dedupe_key = 'orcamento:aceite:' || v_a || ':dados:sombra';
    if v_s.id is null or v_s.tipo is distinct from 'orc_dados_nota' or v_s.enviar_em is distinct from c_t + interval '5 hours 2 minutes'
       or v_s.phone_normalized is distinct from '5547900009953' or v_s.dados ->> 'documento' is distinct from 'CPF'
       or v_s.dados -> 'faltas' is distinct from '["CPF/CNPJ", "rua", "bairro", "cidade", "UF", "CEP"]'::jsonb then
      raise exception '12d: a saída dos dados (%)', to_jsonb(v_s);
    end if;
    -- A pré-condição: decidido de novo, nada é gravado nem agendado (um "Fechado" só).
    v_r := public.orcamento_aceite_registrar(v_a, true, '{"escolha": "com_sinal"}'::jsonb, c_dono, false, c_t + interval '6 hours');
    if v_r is distinct from '{"ok": false, "motivo": "estado"}'::jsonb
       or pg_temp.f5a_saidas(v_a) is distinct from 'orc_dados_nota:sombra:agendada,orc_fechado:sombra:agendada' then
      raise exception '12e: decidido duas vezes (%; %)', v_r, pg_temp.f5a_saidas(v_a);
    end if;
    -- sem_sinal sem executado_em: estado.
    v_m2 := pg_temp.f5a_msg('5547900009953', 'Fechado!', c_t + interval '4 hours 1 minute');
    v_a2 := pg_temp.f5a_aceite(v_m2, v_ana, '00009953', pg_temp.f5a_enviado(v_ana, '5547900009953', 'ORÇ-99358', c_t));
    v_r := public.orcamento_aceite_registrar(v_a2, true, '{"escolha": "sem_sinal"}'::jsonb, c_dono, false, c_t + interval '5 hours');
    if v_r is distinct from '{"ok": false, "motivo": "estado"}'::jsonb or pg_temp.f5a_saidas(v_a2) is distinct from ''
       or (pg_temp.f5a_ac(v_m2)).estado is distinct from 'detectado' then
      raise exception '12f: sem_sinal sem executado_em (%)', v_r;
    end if;
    -- p_ok falso com adiado: executado_em nulo, continua detectado.
    update public.orcamento_aceites set executado_em = c_t + interval '4 hours 50 minutes' where id = v_a2;
    v_r := public.orcamento_aceite_registrar(v_a2, false, '{"escolha": "sem_sinal", "adiado": true}'::jsonb, c_dono, false,
                                             c_t + interval '5 hours');
    if (v_r ->> 'ok')::boolean is not true or (pg_temp.f5a_ac(v_m2)).estado is distinct from 'detectado'
       or (pg_temp.f5a_ac(v_m2)).executado_em is not null or pg_temp.f5a_saidas(v_a2) is distinct from '' then
      raise exception '12g: adiado (%)', v_r;
    end if;
    -- p_ok falso (a conversão falhou): caiu, e nenhuma saída; depois, um caiu não registra.
    update public.orcamento_aceites set executado_em = c_t + interval '4 hours 55 minutes' where id = v_a2;
    v_r := public.orcamento_aceite_registrar(v_a2, false, '{"escolha": "sem_sinal", "erro": "conversao"}'::jsonb, c_dono, false,
                                             c_t + interval '5 hours');
    if (pg_temp.f5a_ac(v_m2)).estado is distinct from 'caiu' or pg_temp.f5a_saidas(v_a2) is distinct from '' then
      raise exception '12h: a conversão falhou (%; %)', v_r, to_jsonb(pg_temp.f5a_ac(v_m2));
    end if;
    v_r := public.orcamento_aceite_registrar(v_a2, true, '{"escolha": "sem_sinal"}'::jsonb, c_dono, false, c_t + interval '6 hours');
    if v_r is distinct from '{"ok": false, "motivo": "estado"}'::jsonb or pg_temp.f5a_saidas(v_a2) is distinct from '' then
      raise exception '12i: caiu registrou (%)', v_r;
    end if;
    -- B/D: sem_sinal com executado_em → sem_sinal e o "Fechado"; de novo → estado, nenhum 2º "Fechado".
    v_m3 := pg_temp.f5a_msg('5547900009953', 'Aprovado', c_t + interval '4 hours 2 minutes');
    v_id := pg_temp.f5a_aceite(v_m3, v_ana, '00009953', pg_temp.f5a_enviado(v_ana, '5547900009953', 'ORÇ-99359', c_t));
    update public.orcamento_aceites set executado_em = c_t + interval '4 hours 58 minutes' where id = v_id;
    v_r := public.orcamento_aceite_registrar(v_id, true, '{"escolha": "sem_sinal", "convertido": true}'::jsonb, c_dono, false,
                                             c_t + interval '5 hours');
    if v_r is distinct from '{"ok": true, "fechado": "sombra", "dados": false}'::jsonb
       or (pg_temp.f5a_ac(v_m3)).estado is distinct from 'sem_sinal' then
      raise exception '12j: sem_sinal com executado_em (%)', v_r;
    end if;
    v_r := public.orcamento_aceite_registrar(v_id, true, '{"escolha": "sem_sinal"}'::jsonb, c_dono, false, c_t + interval '6 hours');
    if v_r is distinct from '{"ok": false, "motivo": "estado"}'::jsonb
       or pg_temp.f5a_saidas(v_id) is distinct from 'orc_fechado:sombra:agendada' then
      raise exception '12k: um "Fechado" só (%; %)', v_r, pg_temp.f5a_saidas(v_id);
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 13. Os dados: a resposta de outro DDD com os mesmos 8 dígitos → continua esperando; a resposta com CPF e CEP do
  --        número da saída → lidos; gravar com o CPF vazio grava; com o CPF preenchido, ja_tinha; o audit_log sem dígito ──
  begin
    v_ana := pg_temp.f5a_cli('Ana Dados F5 Teste', '5547900009954');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009954', 'ORÇ-99360', c_t);
    v_m := pg_temp.f5a_msg('5547900009954', 'Pode fazer.', c_t + interval '4 hours');
    v_a := pg_temp.f5a_aceite(v_m, v_ana, '00009954', v_os, 'com_sinal');
    update public.orcamento_aceites set dados_estado = 'esperando' where id = v_a;
    insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em,
                                       enviada_em, decidida_em, texto, dados, dedupe_key)
    values ('orcamento', 'orc_dados_nota', 'retorno_orcamento', 'resposta_imediata', '00009954', '5547900009954', v_ana, 'ligado',
            'enviada', c_t + interval '5 hours', c_t + interval '5 hours', c_t + interval '5 hours',
            'Ana, para emitir a nota, me passa o CPF e o endereço completo, com CEP? Pode ser por aqui mesmo.',
            jsonb_build_object('aceite_id', v_a), 'orcamento:aceite:' || v_a || ':dados');
    perform pg_temp.f5a_msg('5547900009954', 'Já te passo', c_t + interval '5 hours 10 minutes');
    -- Outra pessoa, com os mesmos 8 dígitos e outro DDD, manda um CPF e um CEP: não é a resposta da Ana (continua esperando).
    v_m3 := pg_temp.f5a_msg('5548900009954', 'CPF 264.983.017-40 e CEP 89000-000', c_t + interval '5 hours 15 minutes');
    v_n := public._orcamento_dados_detectar(c_t + interval '5 hours 17 minutes');
    if v_n is distinct from 0 or (pg_temp.f5a_ac(v_m)).dados_estado is distinct from 'esperando'
       or (pg_temp.f5a_ac(v_m)).dados_msg_id is not null then
      raise exception '13a0: a resposta de outro DDD com os mesmos 8 dígitos virou os dados da Ana (%)', to_jsonb(pg_temp.f5a_ac(v_m));
    end if;
    v_m2 := pg_temp.f5a_msg('5547900009954', 'Meu CPF é 390.533.447-05 e o CEP 88330-000', c_t + interval '5 hours 20 minutes');
    v_n := public._orcamento_dados_detectar(c_t + interval '5 hours 30 minutes');
    v_ac := pg_temp.f5a_ac(v_m);
    if v_n is distinct from 1 or v_ac.dados_estado is distinct from 'lidos' or v_ac.dados_msg_id is distinct from v_m2 then
      raise exception '13a: os dados lidos (%)', to_jsonb(v_ac);
    end if;
    v_r := public.orcamento_dados_gravar(v_a, c_dono, c_t + interval '6 hours');
    if v_r -> 'gravou' is distinct from '["CPF", "CEP"]'::jsonb or v_r -> 'ja_tinha' is distinct from '[]'::jsonb
       or (select c.cpf_cnpj from public.clients c where c.id = v_ana) is distinct from '390.533.447-05'
       or (select c.postal_code from public.clients c where c.id = v_ana) is distinct from '88330-000'
       or (pg_temp.f5a_ac(v_m)).dados_estado is distinct from 'gravados' then
      raise exception '13b: gravar no vazio (%)', v_r;
    end if;
    if exists (select 1 from public.audit_log l
                where l.table_name = 'clients' and l.record_id = v_ana
                  and concat_ws(' ', l.previous_value::text, l.new_value::text, l.reason) ~ '[0-9]') then
      raise exception '13c: o audit_log tem dígito';
    end if;
    -- O cadastro que já tem CPF: não muda, e devolve ja_tinha.
    v_joao := pg_temp.f5a_cli('João Dados F5 Teste', '5547900009955');
    update public.clients set cpf_cnpj = '715.820.164-37' where id = v_joao;
    v_os2 := pg_temp.f5a_enviado(v_joao, '5547900009955', 'ORÇ-99361', c_t);
    v_m3 := pg_temp.f5a_msg('5547900009955', 'Pode fazer.', c_t + interval '4 hours');
    v_a2 := pg_temp.f5a_aceite(v_m3, v_joao, '00009955', v_os2, 'sem_sinal');
    v_id := pg_temp.f5a_msg('5547900009955', 'CPF 264.983.017-40', c_t + interval '5 hours 20 minutes');
    update public.orcamento_aceites set dados_estado = 'lidos', dados_msg_id = v_id where id = v_a2;
    v_r := public.orcamento_dados_gravar(v_a2, c_dono, c_t + interval '6 hours');
    if v_r -> 'gravou' is distinct from '[]'::jsonb or v_r -> 'ja_tinha' is distinct from '["CPF"]'::jsonb
       or (select c.cpf_cnpj from public.clients c where c.id = v_joao) is distinct from '715.820.164-37' then
      raise exception '13d: o CPF já preenchido (%)', v_r;
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 14. Ninguém olha o futuro: a recebida depois de p_agora não entra ──
  begin
    perform pg_temp.f5a_marca(c_t + interval '4 hours');
    v_ana := pg_temp.f5a_cli('Ana Futuro F5 Teste', '5547900009956');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009956', 'ORÇ-99362', c_t);
    v_m := pg_temp.f5a_rm('5547900009956', 'Pode fazer.', c_t + interval '4 hours 20 minutes', c_t + interval '4 hours 5 minutes');
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 10 minutes');
    if (pg_temp.f5a_ac(v_m)).id is not null then
      raise exception '14: a mensagem do futuro entrou';
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 15. O dia do envio no "Fechado": 2 envios ao cliente (01/12 e o revisado em 08/12), mensagem em 09/12 → 08/12 ──
  begin
    v_ana := pg_temp.f5a_cli('Ana Revisado F5 Teste', '5547900009957');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009957', 'ORÇ-99363', '2026-12-01 10:00-03');
    perform pg_temp.f5a_envio(v_os, '5547900009957', '2026-12-08 10:00-03');
    v_m := pg_temp.f5a_msg('5547900009957', 'Pode fazer.', '2026-12-09 10:00-03');
    v_a := pg_temp.f5a_aceite(v_m, v_ana, '00009957', v_os);
    perform public.orcamento_aceite_registrar(v_a, true, '{"escolha": "com_sinal"}'::jsonb, c_dono, false, '2026-12-09 11:00-03');
    if (select s.dados ->> 'dia_envio' from public.retorno_saidas s where s.emissor = 'orcamento' and s.tipo = 'orc_fechado'
                                                                      and s.dados ->> 'aceite_id' = v_a::text) is distinct from '08/12' then
      raise exception '15: o dia do envio no "Fechado"';
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 16. Dois aceites do mesmo cliente: a lista mostra só o mais recente; decidido ele, o mais antigo vai a substituido
  --        (e nenhum 2º "Fechado"); fechar_antigos direto com nao_era, respondido, caiu/pessoal e caiu/orcamento_mudou ──
  begin
    v_ana := pg_temp.f5a_cli('Ana Dois F5 Teste', '5547900009958');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009958', 'ORÇ-99364', c_t - interval '1 day');
    v_m := pg_temp.f5a_rm('5547900009958', 'Pode fazer.', c_t, c_t);
    v_m2 := pg_temp.f5a_rm('5547900009958', 'Fechado!', c_t + interval '1 hour', c_t + interval '1 hour');
    perform pg_temp.f5a_marca(c_t - interval '5 minutes');
    perform public._orcamento_aceites_detectar(c_t + interval '1 hour 5 minutes');
    v_a := (pg_temp.f5a_ac(v_m)).id;
    v_a2 := (pg_temp.f5a_ac(v_m2)).id;
    if v_a is null or v_a2 is null then
      raise exception '16a: as duas linhas não nasceram';
    end if;
    if (select array_agg(l.aceite_id) from public._orcamento_cartao_aceites(c_t + interval '1 hour 5 minutes') l
         where l.aceite_id in (v_a, v_a2)) is distinct from array[v_a2] then
      raise exception '16b: a lista do cartão não mostra só a das 11:00';
    end if;
    v_r := public.orcamento_aceite_registrar(v_a2, true, '{"escolha": "com_sinal"}'::jsonb, c_dono, false, c_t + interval '2 hours');
    v_ac := pg_temp.f5a_ac(v_m);
    if v_ac.estado is distinct from 'substituido' or v_ac.resultado ->> 'substituido_por' is distinct from v_a2::text
       or v_ac.decidido_por is distinct from c_dono or v_ac.decidido_em is distinct from c_t + interval '2 hours'
       or pg_temp.f5a_saidas(v_a) is distinct from '' or pg_temp.f5a_saidas(v_a2) is distinct from 'orc_fechado:sombra:agendada' then
      raise exception '16c: o mais antigo depois do registro (%; %)', to_jsonb(v_ac), v_r;
    end if;
    -- fechar_antigos direto: o recente em nao_era, respondido, caiu/pessoal e caiu/orcamento_mudou.
    for v_rec in
      select * from (values ('nao_era', null, 'substituido'), ('respondido', null, 'substituido'), ('caiu', 'pessoal', 'caiu'),
                            ('caiu', 'orcamento_mudou', 'detectado')) as x(estado, motivo, antigo)
    loop
      update public.orcamento_aceites set estado = 'detectado', resultado = '{}'::jsonb, decidido_em = null, decidido_por = null
       where id = v_a;
      update public.orcamento_aceites
         set estado = v_rec.estado, decidido_em = c_t + interval '3 hours', decidido_por = c_dono,
             resultado = (case when v_rec.motivo is null then '{}'::jsonb else jsonb_build_object('motivo', v_rec.motivo) end)
       where id = v_a2;
      perform public._orcamento_aceite_fechar_antigos(v_a2, c_t + interval '3 hours');
      v_ac := pg_temp.f5a_ac(v_m);
      if v_ac.estado is distinct from v_rec.antigo
         or (v_rec.antigo = 'caiu' and v_ac.resultado ->> 'motivo' is distinct from 'pessoal')
         or (v_rec.antigo = 'substituido' and v_ac.resultado ->> 'substituido_por' is distinct from v_a2::text) then
        raise exception '16d: o recente em %/% deixou o antigo em %', v_rec.estado, v_rec.motivo, to_jsonb(v_ac);
      end if;
    end loop;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 18. Quem escreve, pelo telefone: sem caso, a mensagem do DDD 47 e um só cadastro com os mesmos 8 dígitos no DDD 48 →
  --        nada (quem_escreve do telefone dá ambíguo por ddd_diferente; com a chave, o DDD sairia nulo); e o registro do
  --        aceite gravado à mão não manda o "Fechado" a esse número (numero_compartilhado) ──
  begin
    perform pg_temp.f5a_marca(c_t + interval '4 hours');
    v_pedro := pg_temp.f5a_cli('Pedro Outro DDD F5 Teste', '5548900009918');
    v_os := pg_temp.f5a_enviado(v_pedro, '5548900009918', 'ORÇ-99365', c_t);
    if public.quem_escreve('5547900009918') ->> 'papel' is distinct from 'cliente_ambiguo'
       or public.quem_escreve('00009918') ->> 'papel' is distinct from 'cliente' then
      raise exception '18a: a premissa de quem_escreve (DDD) mudou';
    end if;
    v_m := pg_temp.f5a_rm('5547900009918', 'Pode fazer.', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes');
    perform public._orcamento_aceites_detectar(c_t + interval '4 hours 10 minutes');
    if (pg_temp.f5a_ac(v_m)).id is not null then
      raise exception '18b: a mensagem de outro DDD virou aceite do cadastro';
    end if;
    -- O registro confere de novo (o aceite gravado à mão, sem caso): o "Fechado" não sai ao número de outro DDD.
    v_a := pg_temp.f5a_aceite(v_m, v_pedro, '00009918', v_os);
    v_r := public.orcamento_aceite_registrar(v_a, true, '{"escolha": "com_sinal"}'::jsonb, c_dono, false, c_t + interval '5 hours');
    if v_r is distinct from '{"ok": true, "fechado": null, "dados": false, "motivo": "numero_compartilhado"}'::jsonb
       or pg_temp.f5a_saidas(v_a) is distinct from ''
       or (pg_temp.f5a_ac(v_m)).resultado ->> 'saida_nao_saiu' is distinct from 'numero_compartilhado' then
      raise exception '18c: o registro sem caso mandou o "Fechado" a outro DDD (%; %)', v_r, pg_temp.f5a_saidas(v_a);
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 18b. Com caso: a Ana (DDD 48) tem o caso vivo e o orçamento enviado, e de outro DDD com os mesmos 8 dígitos chega
  --         "Pode fazer.". O retorno_abrir junta essa mensagem ao caso dela só pela chave; o aceite não nasce em nome dela, e o
  --         registro (com o aceite gravado à mão) não manda o "Fechado" a esse número. A dela, do número dela, vira aceite ──
  begin
    v_ana := pg_temp.f5a_cli('Ana Caso DDD F5 Teste', '5548900009919');
    v_os := pg_temp.f5a_enviado(v_ana, '5548900009919', 'ORÇ-99367', v_agora - interval '3 hours');
    perform pg_temp.f5a_marca(v_agora - interval '5 minutes');
    v_m := pg_temp.f5a_msg('5548900009919', 'A peça já chegou?', v_agora - interval '2 hours');
    v_r := public.retorno_abrir(v_m, true, v_agora);
    v_ab := (v_r ->> 'abertura_id')::uuid;
    if v_ab is null
       or not exists (select 1 from public.retorno_aberturas ab where ab.id = v_ab and ab.papel = 'cliente' and ab.client_id = v_ana) then
      raise exception '18d: o caso da Ana não abriu com o papel cliente (%)', v_r;
    end if;
    v_m2 := pg_temp.f5a_msg('5547900009919', 'Pode fazer.', v_agora - interval '90 minutes');
    perform public.retorno_abrir(v_m2, false, v_agora);
    if (select rm.abertura_id from public.retorno_mensagens rm where rm.whatsapp_message_id = v_m2) is distinct from v_ab then
      raise exception '18e: a premissa mudou: a mensagem do DDD 47 não entrou no caso da Ana pela chave';
    end if;
    v_m3 := pg_temp.f5a_msg('5548900009919', 'Fechado!', v_agora - interval '80 minutes');
    perform public.retorno_abrir(v_m3, false, v_agora);
    perform public._orcamento_aceites_detectar(v_agora + interval '1 minute');
    if (pg_temp.f5a_ac(v_m2)).id is not null then
      raise exception '18f: a mensagem de outro DDD no caso da Ana virou aceite dela (%)', to_jsonb(pg_temp.f5a_ac(v_m2));
    end if;
    v_ac := pg_temp.f5a_ac(v_m3);
    if v_ac.estado is distinct from 'detectado' or v_ac.abertura_id is distinct from v_ab or v_ac.client_id is distinct from v_ana
       or v_ac.service_order_id is distinct from v_os then
      raise exception '18g: a mensagem da Ana, do número dela, no caso dela (%)', to_jsonb(v_ac);
    end if;
    -- O registro confere de novo, pelo caso: o aceite da mensagem do DDD 47 (gravado à mão, no caso da Ana) não manda nada.
    v_a := pg_temp.f5a_aceite(v_m2, v_ana, '00009919', v_os);
    update public.orcamento_aceites set abertura_id = v_ab where id = v_a;
    v_r := public.orcamento_aceite_registrar(v_a, true, '{"escolha": "com_sinal"}'::jsonb, c_dono, true, v_agora + interval '2 minutes');
    if v_r is distinct from '{"ok": true, "fechado": null, "dados": false, "motivo": "numero_compartilhado"}'::jsonb
       or pg_temp.f5a_saidas(v_a) is distinct from ''
       or (pg_temp.f5a_ac(v_m2)).resultado ->> 'saida_nao_saiu' is distinct from 'numero_compartilhado' then
      raise exception '18h: o registro no caso da Ana mandou o "Fechado" ao DDD 47 (%; %)', v_r, pg_temp.f5a_saidas(v_a);
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 19. O vigia (P3) com a cadência desligada e o aceite em sombra: o aceite continua sendo medido (P3.2 nº 13) ──
  begin
    update public.retorno_config set orcamento_modo = 'desligado', aceite_modo = 'sombra' where id;
    perform pg_temp.f5a_marca(c_t + interval '4 hours');
    v_ana := pg_temp.f5a_cli('Ana Vigia F5 Teste', '5547900009959');
    v_os := pg_temp.f5a_enviado(v_ana, '5547900009959', 'ORÇ-99366', c_t);
    v_m := pg_temp.f5a_rm('5547900009959', 'Pode fazer.', c_t + interval '4 hours 5 minutes', c_t + interval '4 hours 5 minutes');
    v_r := public.orcamento_vigia(c_t + interval '4 hours 10 minutes');
    if (pg_temp.f5a_ac(v_m)).estado is distinct from 'sombra' or (v_r ->> 'aceites')::integer is distinct from 1
       or exists (select 1 from public.orcamento_acompanhamentos a where a.service_order_id = v_os) then
      raise exception '19: o vigia com a cadência desligada (%; %)', v_r, to_jsonb(pg_temp.f5a_ac(v_m));
    end if;
    raise exception 'f5a_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5a_cenario' then
      raise;
    end if;
  end;

  -- ── 20. As funções novas: SECURITY DEFINER com search_path, fechadas a anon e authenticated; as 3 públicas abertas à
  --        service_role; nenhuma função do orçamento aberta a anon ──
  foreach v in array c_novas loop
    for v_rec in
      select p.oid, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v
    loop
      v_n_fun := v_n_fun + 1;
      if v_rec.prosecdef is not true or not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
        raise exception '20a: % não é SECURITY DEFINER com search_path', v_rec.nome;
      end if;
      if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute') then
        raise exception '20b: % aberta a anon ou authenticated', v_rec.nome;
      end if;
      if v = any (c_publicas) and not has_function_privilege('service_role', v_rec.oid, 'execute') then
        raise exception '20c: % sem o grant da service_role', v_rec.nome;
      end if;
    end loop;
  end loop;
  if v_n_fun is distinct from 14 then
    raise exception '20d: achei % das 14 funções novas', v_n_fun;
  end if;
  v_n_fun := 0;
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?orcamento'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_rec.oid, 'execute') then
      raise exception '20e: % aberta a anon', v_rec.nome;
    end if;
    if has_function_privilege('authenticated', v_rec.oid, 'execute')
       and v_rec.proname <> all (array['orcamento_validade_do_envio', 'orcamentos_para_agrupar']) then
      raise exception '20f: % aberta a authenticated', v_rec.nome;
    end if;
  end loop;
  if v_n_fun < 25 then
    raise exception '20g: a varredura das funções do orçamento achou só % (o filtro quebrou)', v_n_fun;
  end if;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_aceite', true, '{}');
end
$aceite$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
