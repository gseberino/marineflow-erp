-- Retorno F5 (P4): os textos do orçamento O01–O22, a {validade}, o dia do envio aprovado, a legenda do PDF (O21 e O22), o
-- {do_servico}, a variante, o contexto do validador, a apresentação (_cliente_ja_apresentada gerada) e os nomes curtos dos
-- tipos novos (_retorno_tipo_curto gerada). Roda só pela bancada (grupo 8, F5_ONDA=2, F5_TESTES=retorno_f5_textos). Termina
-- em ROLLBACK, e o bloco se desfaz sozinho. Só confere as próprias linhas sintéticas: telefones inventados 55479000151xx (a
-- chave sai do telefone: 000151xx), nomes inventados (Ana, João, Pedro), números de documento inventados (ORÇ-9915x).
-- Nenhuma mensagem real é lida: as recebidas do item 9 são inventadas e só existem dentro da transação. Relógio: ter
-- 12/01/2027 10:00 (Brasília).
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f5t_cli(p_nome text, p_fone text, p_tipo text default 'individual', p_exibicao text default null)
returns uuid
language sql as $f$
  insert into public.clients (type, name, display_name, whatsapp) values (p_tipo, p_nome, p_exibicao, p_fone) returning id
$f$;

create or replace function pg_temp.f5t_orc(p_cliente uuid, p_numero text, p_descricao text default null) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, grand_total,
                                     problem_description)
  values (p_numero, p_cliente, v_v, 'draft', 'draft', 'repair', 100, p_descricao)
  returning id into v_id;
  return v_id;
end $f$;

create or replace function pg_temp.f5t_igual(p_rotulo text, p_obtido text, p_esperado text) returns void
language plpgsql as $f$
begin
  if p_obtido is distinct from p_esperado then
    raise exception '%: obtido %, esperado %', p_rotulo, coalesce(p_obtido, '(nulo)'), coalesce(p_esperado, '(nulo)');
  end if;
end $f$;

create or replace function pg_temp.f5t_esperar_22023(p_tipo text, p_variante text, p_dados jsonb, p_rotulo text) returns void
language plpgsql as $f$
declare
  v text;
begin
  begin
    v := public._orcamento_texto(p_tipo, p_variante, p_dados);
  exception when sqlstate '22023' then
    return;
  end;
  raise exception '%: esperava 22023, saiu %', p_rotulo, coalesce(v, '(nulo)');
end $f$;

-- Uma saída do retorno já decidida (ou só agendada), para a apresentação e o contexto.
create or replace function pg_temp.f5t_saida(p_emissor text, p_tipo text, p_origem text, p_classe text, p_fone text, p_cliente uuid,
                                             p_estado text, p_em timestamptz, p_chave_dedupe text) returns uuid
language sql as $f$
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em,
                                     decidida_em, enviada_em, texto, dedupe_key)
  values (p_emissor, p_tipo, p_origem, p_classe, public._agenda_chave_telefone(p_fone), p_fone, p_cliente,
          case when p_estado = 'sombra' then 'sombra' else 'ligado' end, p_estado, p_em,
          case when p_estado = 'agendada' then null else p_em end,
          case when p_estado = 'enviada' then p_em end,
          case when p_estado = 'agendada' then null else 'Texto de teste da F5.' end,
          p_chave_dedupe)
  returning id
$f$;

-- Uma recebida inventada (só existe dentro da transação; sem dígitos, para a máscara de PIN não mexer).
create or replace function pg_temp.f5t_recebida(p_fone text, p_corpo text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at, hora_real)
  values ('inbound', p_fone, 'text', p_corpo, 'teste-f5-textos-' || md5(p_fone || p_corpo || p_em::text || random()::text), p_em, p_em)
  returning id
$f$;

do $textos$
declare
  c_t constant timestamptz := '2027-01-12 10:00-03';        -- ter
  c_hoje constant date := '2027-01-12';
  c_fone_ana constant text := '5547900015101';
  c_chave_ana constant text := '00015101';
  -- 2c. As duas fontes da O21: a legenda padrão de legendaDoPdf (whatsapp.ts, 20/10) e o trecho da L01 (20261208100300).
  c_legenda_padrao constant text := 'Segue o {numero}, conforme solicitado. Qualquer dúvida, estamos à disposição.';
  c_trecho_l01 constant text := 'Ele vale até {validade}.';
  c_pares constant text[] := array[
    'orc_lembrete/padrao', 'orc_lembrete/padrao_apresentacao', 'orc_lembrete/sem_servico', 'orc_lembrete/sem_servico_apresentacao',
    'orc_vespera/padrao', 'orc_vespera/padrao_apresentacao', 'orc_vespera/sem_servico', 'orc_vespera/sem_servico_apresentacao',
    'orc_encerramento/padrao', 'orc_encerramento/padrao_apresentacao', 'orc_encerramento/sem_servico',
    'orc_encerramento/sem_servico_apresentacao', 'orc_fechado/padrao', 'orc_fechado/padrao_apresentacao', 'orc_fechado/sem_servico',
    'orc_fechado/sem_servico_apresentacao', 'orc_dados_nota/cpf_endereco', 'orc_dados_nota/cnpj_endereco', 'orc_dados_nota/documento',
    'orc_dados_nota/endereco', 'orc_legenda/padrao', 'orc_legenda/linha'];
  d_ok constant jsonb := '{"nome": "Ana", "do_servico": "das baterias", "validade": "terça (19/01)", "dia_envio": "05/01",
                           "numero": "ORÇ-99151", "documento": "CPF"}';
  -- 5. Os valores mais longos de cada campo (o tamanho), e os que levam dígito (o resto do texto não pode ter dígito).
  d_longo constant jsonb := '{"nome": "Bartolomeu", "do_servico": "da antena Starlink e dos equipamentos de navegação",
                              "validade": "domingo (17/01)", "dia_envio": "31/12", "numero": "ORÇ-12345678", "documento": "CNPJ"}';
  c_novas constant text[] := array['_orcamento_texto', '_orcamento_do_servico', '_orcamento_validade_texto', '_orcamento_variante',
                                   '_orcamento_contexto_do_validador', '_orcamento_dia_envio', '_orcamento_legenda'];
  -- Funções do orçamento abertas a authenticated de propósito: orcamento_validade_do_envio (P2: confere o cargo) e
  -- orcamentos_para_agrupar (anterior à F5). Nenhuma aberta a anon.
  c_abertas constant text[] := array['orcamento_validade_do_envio', 'orcamentos_para_agrupar'];
  v_par text;
  v_t text;
  v_r jsonb;
  v_ctx jsonb;
  v_chaves text[];
  v_ana uuid; v_joao uuid; v_pedro uuid; v_bia uuid; v_empresa uuid; v_empresa2 uuid; v_sem_nome uuid;
  v_os uuid; v_os_tres uuid; v_os_duas uuid; v_os_linha uuid; v_os_nada uuid;
  v_aceite uuid;
  v_s uuid;
  v_rec record;
  v_n_fun integer := 0;
begin
  begin
  v_ana := pg_temp.f5t_cli('Ana Textos F5', c_fone_ana);
  v_os := pg_temp.f5t_orc(v_ana, 'ORÇ-99152', 'Troca de bateria da lancha');

  -- ── 1. Os 22 pares, e as recusas (par, tipo, variante, campo faltando ou fora da forma) ──
  foreach v_par in array c_pares loop
    v_t := public._orcamento_texto(split_part(v_par, '/', 1), split_part(v_par, '/', 2), d_ok);
    if v_t is null or v_t ~ '[{}]' or char_length(v_t) < 10 then
      raise exception '1a: o par % não gerou texto (%)', v_par, v_t;
    end if;
  end loop;
  perform pg_temp.f5t_igual('1b O01', public._orcamento_texto('orc_lembrete', 'padrao', d_ok),
    'Oi, Ana! Conseguiu ver o orçamento das baterias? Se tiver alguma dúvida ou quiser ajustar algo, é só responder por aqui que eu passo ao Gustavo.');
  perform pg_temp.f5t_igual('1c O13', public._orcamento_texto('orc_fechado', 'padrao', d_ok),
    'Fechado, Ana! Anotei a aprovação do orçamento das baterias de 05/01. O Gustavo te passa a data por aqui.');
  perform pg_temp.f5t_igual('1d O19', public._orcamento_texto('orc_dados_nota', 'documento', d_ok),
    'Ana, para emitir a nota, me passa o CPF? Pode ser por aqui mesmo.');
  perform pg_temp.f5t_esperar_22023('orc_lembrete', 'sem_nome', d_ok, '1e variante sem_nome (a saída cai com sem_nome)');
  perform pg_temp.f5t_esperar_22023('orc_lembrete', 'nao_existe', d_ok, '1f variante desconhecida');
  perform pg_temp.f5t_esperar_22023('outro', 'padrao', d_ok, '1g tipo desconhecido');
  perform pg_temp.f5t_esperar_22023('orc_lembrete', null, d_ok, '1h variante nula');
  perform pg_temp.f5t_esperar_22023('orc_lembrete', 'padrao', d_ok - 'nome', '1i sem nome');
  perform pg_temp.f5t_esperar_22023('orc_lembrete', 'padrao', d_ok || '{"nome": "  "}', '1j nome em branco');
  perform pg_temp.f5t_esperar_22023('orc_lembrete', 'padrao', d_ok - 'do_servico', '1k sem do_servico');
  perform pg_temp.f5t_esperar_22023('orc_vespera', 'padrao', d_ok || '{"validade": "semana que vem"}', '1l validade fora da forma');
  perform pg_temp.f5t_esperar_22023('orc_vespera', 'padrao', d_ok || '{"validade": "terça 19/01"}', '1m validade sem parênteses');
  perform pg_temp.f5t_esperar_22023('orc_vespera', 'sem_servico', d_ok - 'validade', '1n sem validade');
  perform pg_temp.f5t_esperar_22023('orc_fechado', 'padrao', d_ok || '{"dia_envio": "5/1"}', '1o dia_envio fora da forma');
  perform pg_temp.f5t_esperar_22023('orc_legenda', 'padrao', d_ok || '{"numero": "ORÇ-TF5"}', '1p número fora da forma');
  perform pg_temp.f5t_esperar_22023('orc_dados_nota', 'documento', d_ok || '{"documento": "RG"}', '1q documento fora da lista');
  perform pg_temp.f5t_esperar_22023('orc_lembrete', 'padrao', '[]'::jsonb, '1r dados que não são objeto');

  -- ── 2. A {validade} ──
  perform pg_temp.f5t_igual('2a hoje', public._orcamento_validade_texto(c_hoje, c_hoje), 'hoje');
  perform pg_temp.f5t_igual('2b amanhã', public._orcamento_validade_texto(c_hoje + 1, c_hoje), 'amanhã');
  perform pg_temp.f5t_igual('2c terça seguinte', public._orcamento_validade_texto(c_hoje + 7, c_hoje), 'terça (19/01)');
  perform pg_temp.f5t_igual('2d sábado', public._orcamento_validade_texto(date '2027-01-16', c_hoje), 'sábado (16/01)');
  perform pg_temp.f5t_igual('2e já passou', public._orcamento_validade_texto(c_hoje - 1, c_hoje), null);
  perform pg_temp.f5t_igual('2f sem data', public._orcamento_validade_texto(null, c_hoje), null);

  -- ── 2b. O dia do envio que o cliente aprovou: o último ao cliente, na mesma chave, antes da mensagem ──
  insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, marcou) values
    (v_os, v_ana, 'tela', c_chave_ana, true, '2027-01-05 10:00-03', true),
    (v_os, v_ana, 'assistente', c_chave_ana, true, '2027-01-12 09:00-03', false),
    (v_os, v_ana, 'aparelho', '00015199', false, '2027-01-08 10:00-03', false),      -- a outro número
    (v_os, v_ana, 'cartao', '00015102', true, '2027-01-08 11:00-03', false);         -- ao cliente, mas outra chave
  perform pg_temp.f5t_igual('2b1 depois do reenvio', public._orcamento_dia_envio(v_os, c_chave_ana, '2027-01-13 09:00-03')::text, '2027-01-12');
  perform pg_temp.f5t_igual('2b2 antes do reenvio', public._orcamento_dia_envio(v_os, c_chave_ana, '2027-01-09 09:00-03')::text, '2027-01-05');
  perform pg_temp.f5t_igual('2b3 antes de todo envio', public._orcamento_dia_envio(v_os, c_chave_ana, '2027-01-05 09:00-03')::text, null);
  perform pg_temp.f5t_igual('2b4 a outra chave do cliente', public._orcamento_dia_envio(v_os, '00015102', '2027-01-13 09:00-03')::text, '2027-01-08');

  -- ── 2c. A legenda: O21 e O22 preenchidos, iguais às duas fontes, letra por letra ──
  v_r := public._orcamento_legenda(v_os, c_hoje + 7, c_t);
  perform pg_temp.f5t_igual('2c1 O21', v_r ->> 'legenda',
    replace(replace(replace(c_legenda_padrao, 'solicitado. Qualquer', 'solicitado. ' || c_trecho_l01 || ' Qualquer'),
                    '{numero}', 'ORÇ-99152'), '{validade}', 'terça (19/01)'));
  perform pg_temp.f5t_igual('2c2 O21 literal', v_r ->> 'legenda',
    'Segue o ORÇ-99152, conforme solicitado. Ele vale até terça (19/01). Qualquer dúvida, estamos à disposição.');
  perform pg_temp.f5t_igual('2c3 O22', v_r ->> 'linha', replace(c_trecho_l01, '{validade}', 'terça (19/01)'));
  -- O trecho da L01 é o do banco (a legenda da F3 continua igual).
  if (strpos(public._retorno_texto_f3('orcamento_pdf', 'padrao', '{"nome": "Ana", "do_servico": "das baterias", "validade": "terça (19/01)"}'),
             replace(c_trecho_l01, '{validade}', 'terça (19/01)')) > 0) is not true then
    raise exception '2c4: o trecho "Ele vale até" não está mais na L01 do banco';
  end if;
  v_ctx := v_r -> 'contexto';
  select array_agg(k order by k) into v_chaves from jsonb_object_keys(v_ctx) k;
  if v_chaves is distinct from array['audiencia', 'datas_permitidas', 'horas_permitidas', 'marcas', 'nome_permitido', 'nomes_de_outros',
                                     'os_permitidas', 'textos_do_cliente', 'trechos_do_modelo'] then
    raise exception '2c5: chaves do contexto da legenda (%)', v_chaves;
  end if;
  if v_ctx ->> 'audiencia' is distinct from 'cliente'
     or v_ctx -> 'os_permitidas' is distinct from '["ORÇ-99152"]'::jsonb
     or v_ctx -> 'datas_permitidas' is distinct from '["terça (19/01)"]'::jsonb
     or jsonb_typeof(v_ctx -> 'nome_permitido') is distinct from 'null'
     or v_ctx -> 'horas_permitidas' is distinct from '[]'::jsonb
     or v_ctx -> 'textos_do_cliente' is distinct from '[]'::jsonb
     or v_ctx -> 'marcas' is distinct from '{"tem_proposta": false, "tem_topo": false, "cliente_ouviu": false, "conferida": false, "aceite_registrado": false}'::jsonb then
    raise exception '2c6: contexto da legenda: %', v_ctx;
  end if;
  perform pg_temp.f5t_igual('2c7 trechos da legenda', v_ctx ->> 'trechos_do_modelo',
    '["Segue o ", ", conforme solicitado. Ele vale até ", ". Qualquer dúvida, estamos à disposição.", "Ele vale até ", "."]');
  perform pg_temp.f5t_igual('2c8 hoje', public._orcamento_legenda(v_os, c_hoje, c_t) ->> 'linha', 'Ele vale até hoje.');
  begin
    v_r := public._orcamento_legenda(v_os, c_hoje - 1, c_t);
    raise exception '2c9: legenda com a data já vencida saiu (%)', v_r;
  exception when sqlstate '22023' then
    null;
  end;

  -- ── 3. O {do_servico}: só o texto do dono (descrição e linhas) ──
  perform pg_temp.f5t_igual('3a bateria', public._orcamento_do_servico(v_os), 'das baterias');
  v_os_tres := pg_temp.f5t_orc(v_ana, 'ORÇ-99153', 'Bateria, painel solar e inversor');
  perform pg_temp.f5t_igual('3b três famílias', public._orcamento_do_servico(v_os_tres), null);
  v_os_duas := pg_temp.f5t_orc(v_ana, 'ORÇ-99154', 'Baterias de lítio e placas solares');
  perform pg_temp.f5t_igual('3c duas famílias', public._orcamento_do_servico(v_os_duas), 'das baterias e de energia solar');
  v_os_linha := pg_temp.f5t_orc(v_ana, 'ORÇ-99155', null);
  insert into public.service_order_services (service_order_id, name_snapshot) values (v_os_linha, 'Instalação de inversor');
  perform pg_temp.f5t_igual('3d pela linha de serviço', public._orcamento_do_servico(v_os_linha), 'do inversor');
  v_os_nada := pg_temp.f5t_orc(v_ana, 'ORÇ-99156', 'Revisão elétrica geral');
  perform pg_temp.f5t_igual('3e nenhuma família', public._orcamento_do_servico(v_os_nada), null);
  perform pg_temp.f5t_igual('3f ordem que não existe', public._orcamento_do_servico(gen_random_uuid()), null);
  if (select p.prosrc ~* '(whatsapp_messages|retorno_mensagens)' from pg_proc p
       where p.oid = 'public._orcamento_do_servico(uuid)'::regprocedure) is not false then
    raise exception '3g: _orcamento_do_servico lê mensagem';
  end if;

  -- ── 4. _cliente_ja_apresentada: a saída do orçamento enviada conta; sombra, incerta e agendada não; a F1 e a F4 iguais ──
  v_pedro := pg_temp.f5t_cli('Pedro Textos F5', '5547900015103');
  if public._cliente_ja_apresentada(v_pedro, '00015103', c_hoje) is not false then
    raise exception '4a: cliente novo já apresentado';
  end if;
  perform pg_temp.f5t_saida('orcamento', 'orc_lembrete', 'retorno_orcamento', 'comercial', '5547900015103', v_pedro, 'sombra',
                            c_t - interval '1 day', 'orcamento:teste-f5-textos:4b');
  perform pg_temp.f5t_saida('orcamento', 'orc_vespera', 'retorno_orcamento', 'comercial', '5547900015103', v_pedro, 'incerta',
                            c_t - interval '1 day', 'orcamento:teste-f5-textos:4c');
  perform pg_temp.f5t_saida('orcamento', 'orc_encerramento', 'retorno_orcamento', 'comercial', '5547900015103', v_pedro, 'agendada',
                            c_t - interval '1 day', 'orcamento:teste-f5-textos:4d');
  if public._cliente_ja_apresentada(v_pedro, '00015103', c_hoje) is not false then
    raise exception '4b: saída do orçamento em sombra, incerta ou agendada contou como apresentação';
  end if;
  perform pg_temp.f5t_saida('orcamento', 'orc_lembrete', 'retorno_orcamento', 'comercial', '5547900015103', v_pedro, 'enviada',
                            c_t - interval '1 day', 'orcamento:teste-f5-textos:4e');
  if public._cliente_ja_apresentada(v_pedro, '00015103', c_hoje) is not true
     or public._cliente_ja_apresentada(null, '00015103', c_hoje) is not true
     or public._cliente_ja_apresentada(v_pedro, null, c_hoje) is not true then
    raise exception '4c: a saída do orçamento enviada não contou (por cliente e por chave)';
  end if;
  -- Regressão da F1: o recibo enviado conta; o da F4: o aviso ao cliente final enviado conta.
  v_joao := pg_temp.f5t_cli('João Textos F5', '5547900015104');
  perform pg_temp.f5t_saida('retorno', 'recibo_cliente', 'retorno_recibo', 'resposta_imediata', '5547900015104', v_joao, 'enviada',
                            c_t - interval '2 days', 'retorno:teste-f5-textos:4f');
  if public._cliente_ja_apresentada(v_joao, '00015104', c_hoje) is not true then
    raise exception '4d: regressão da F1 (recibo enviado)';
  end if;
  v_bia := pg_temp.f5t_cli('Bia Textos F5', '5547900015105');
  perform pg_temp.f5t_saida('parceiro', 'parceiro_aviso_cliente', 'retorno_aviso', 'aviso', '5547900015105', v_bia, 'enviada',
                            c_t - interval '2 days', 'parceiro:teste-f5-textos:4g');
  if public._cliente_ja_apresentada(v_bia, '00015105', c_hoje) is not true then
    raise exception '4e: regressão da F4 (aviso ao cliente final enviado)';
  end if;
  -- O que sai no futuro de p_hoje não conta.
  if public._cliente_ja_apresentada(v_pedro, '00015103', c_hoje - 3) is not false then
    raise exception '4f: a apresentação olhou o futuro';
  end if;

  -- ── 5. Cada texto: até 400 caracteres e 5 linhas, sem emoji, sem dígito fora de {dia_envio}, {validade} e {numero} ──
  foreach v_par in array c_pares loop
    v_t := public._orcamento_texto(split_part(v_par, '/', 1), split_part(v_par, '/', 2), d_longo);
    if (char_length(v_t) <= 400 and cardinality(regexp_split_to_array(v_t, '\n')) <= 5) is not true then
      raise exception '5a: % passa de 400 caracteres ou 5 linhas (%)', v_par, char_length(v_t);
    end if;
    if (v_t ~ '[\U0001F000-\U0001FAFF☀-➿️‍]') is not false then
      raise exception '5b: % tem emoji', v_par;
    end if;
    if (replace(replace(replace(v_t, d_longo ->> 'validade', ''), d_longo ->> 'dia_envio', ''), d_longo ->> 'numero', '') ~ '[0-9]') is not false then
      raise exception '5c: % tem dígito fora dos campos (%)', v_par, v_t;
    end if;
  end loop;

  -- ── 6. _retorno_tipo_curto: os 5 tipos da F5 e os de antes iguais ──
  for v_rec in
    select x.tipo, x.curto from (values
      ('orc_lembrete', 'lembrete do orçamento'), ('orc_vespera', 'véspera do orçamento'),
      ('orc_encerramento', 'encerramento do orçamento'), ('orc_fechado', 'fechado do orçamento'), ('orc_dados_nota', 'dados da nota'),
      ('modelo_aguarda_peca', 'aguardando peça'), ('modelo_peca_chegou', 'peça chegou'), ('modelo_pronto', 'pronto'),
      ('modelo_em_servico', 'em serviço'), ('modelo_liberado', 'liberado'), ('modelo_retirada_nao', 'retirada ainda não'),
      ('modelo_ver_no_local', 'ver no local')) as x(tipo, curto)
  loop
    perform pg_temp.f5t_igual('6a ' || v_rec.tipo, public._retorno_tipo_curto(v_rec.tipo), v_rec.curto);
  end loop;
  perform pg_temp.f5t_igual('6b tipo desconhecido', public._retorno_tipo_curto('inventado'), null);

  -- ── 7. A variante ──
  perform pg_temp.f5t_igual('7a nunca apresentada', public._orcamento_variante('orc_lembrete', v_os, v_ana, c_chave_ana, c_hoje, '{}'),
                            'padrao_apresentacao');
  perform pg_temp.f5t_igual('7b sem família', public._orcamento_variante('orc_vespera', v_os_nada, v_ana, c_chave_ana, c_hoje, '{}'),
                            'sem_servico_apresentacao');
  perform pg_temp.f5t_saida('orcamento', 'orc_lembrete', 'retorno_orcamento', 'comercial', c_fone_ana, v_ana, 'enviada',
                            c_t - interval '1 day', 'orcamento:teste-f5-textos:7c');
  perform pg_temp.f5t_igual('7c já apresentada', public._orcamento_variante('orc_encerramento', v_os, v_ana, c_chave_ana, c_hoje, '{}'),
                            'padrao');
  perform pg_temp.f5t_igual('7d fechado sem família', public._orcamento_variante('orc_fechado', v_os_nada, v_ana, c_chave_ana, c_hoje, '{}'),
                            'sem_servico');
  v_sem_nome := pg_temp.f5t_cli('Empresa Sem Nome Curto F5', '5547900015106', 'company', null);
  perform pg_temp.f5t_igual('7e sem nome', public._orcamento_variante('orc_lembrete', v_os, v_sem_nome, '00015106', c_hoje, '{}'), 'sem_nome');
  perform pg_temp.f5t_igual('7f dados: documento e endereço',
    public._orcamento_variante('orc_dados_nota', v_os, v_ana, c_chave_ana, c_hoje, '{"faltas": ["CPF/CNPJ", "CEP"]}'), 'cpf_endereco');
  v_empresa := pg_temp.f5t_cli('Oficina Teste F5 Ltda', '5547900015107', 'company', 'Pedro');
  perform pg_temp.f5t_igual('7g dados: empresa',
    public._orcamento_variante('orc_dados_nota', v_os, v_empresa, '00015107', c_hoje, '{"faltas": ["CPF/CNPJ incompleto", "rua"]}'),
    'cnpj_endereco');
  perform pg_temp.f5t_igual('7h dados: só documento',
    public._orcamento_variante('orc_dados_nota', v_os, v_ana, c_chave_ana, c_hoje, '{"faltas": ["CPF/CNPJ incompleto"]}'), 'documento');
  perform pg_temp.f5t_igual('7i dados: só endereço',
    public._orcamento_variante('orc_dados_nota', v_os, v_ana, c_chave_ana, c_hoje, '{"faltas": ["bairro", "UF"]}'), 'endereco');
  perform pg_temp.f5t_igual('7j dados: nada a pedir',
    public._orcamento_variante('orc_dados_nota', v_os, v_ana, c_chave_ana, c_hoje, '{"faltas": ["inscrição estadual"]}'), null);
  insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado, faltas_nota)
    values (gen_random_uuid(), v_ana, c_chave_ana, array[v_os], v_os, 'pode fazer', 'sem_sinal', array['CPF/CNPJ', 'cidade'])
    returning id into v_aceite;
  perform pg_temp.f5t_igual('7k dados: as faltas do aceite',
    public._orcamento_variante('orc_dados_nota', v_os, v_ana, c_chave_ana, c_hoje, jsonb_build_object('aceite_id', v_aceite)), 'cpf_endereco');
  begin
    v_t := public._orcamento_variante('orc_legenda', v_os, v_ana, c_chave_ana, c_hoje, '{}');
    raise exception '7l: tipo fora da lista deu variante (%)', v_t;
  exception when sqlstate '22023' then
    null;
  end;

  -- ── 8. O contexto do validador ──
  -- Outro cliente no mesmo número da Ana (o nome dele nunca pode sair) e as recebidas da chave: 31 dias antes (fora), ontem
  -- (dentro) e depois de p_agora (fora: ninguém olha o futuro).
  v_empresa2 := pg_temp.f5t_cli('Joana Textos F5', c_fone_ana);
  perform pg_temp.f5t_recebida(c_fone_ana, 'FRASE-F5-TEXTOS-ANTIGA conversa velha', c_t - interval '31 days');
  perform pg_temp.f5t_recebida(c_fone_ana, 'FRASE-F5-TEXTOS pode fazer o orçamento', c_t - interval '1 day');
  perform pg_temp.f5t_recebida(c_fone_ana, 'FRASE-F5-TEXTOS-FUTURA depois', c_t + interval '1 hour');
  v_s := pg_temp.f5t_saida('orcamento', 'orc_fechado', 'retorno_orcamento', 'resposta_imediata', c_fone_ana, v_ana, 'agendada', c_t,
                           'orcamento:teste-f5-textos:8a');
  v_t := public._orcamento_texto('orc_fechado', 'padrao', '{"nome": "Ana", "do_servico": "das baterias", "dia_envio": "12/01"}');
  v_ctx := public._orcamento_contexto_do_validador(v_s, v_t, '{"nome": "Ana", "do_servico": "das baterias", "dia_envio": "12/01"}', c_t);
  select array_agg(k order by k) into v_chaves from jsonb_object_keys(v_ctx) k;
  if v_chaves is distinct from array['audiencia', 'datas_permitidas', 'horas_permitidas', 'marcas', 'nome_permitido', 'nomes_de_outros',
                                     'os_permitidas', 'textos_do_cliente', 'trechos_do_modelo'] then
    raise exception '8a: chaves do contexto (%)', v_chaves;
  end if;
  if v_ctx ->> 'audiencia' is distinct from 'cliente' or v_ctx ->> 'nome_permitido' is distinct from 'Ana'
     or v_ctx -> 'datas_permitidas' is distinct from '["12/01"]'::jsonb
     or v_ctx -> 'horas_permitidas' is distinct from '[]'::jsonb
     or v_ctx -> 'os_permitidas' is distinct from '[]'::jsonb
     or (v_ctx -> 'nomes_de_outros' @> '["Joana"]'::jsonb) is not true
     or (v_ctx -> 'nomes_de_outros' @> '["Ana"]'::jsonb) is not false then
    raise exception '8b: listas do contexto: %', v_ctx;
  end if;
  if (v_ctx -> 'marcas' ->> 'aceite_registrado')::boolean is not true or (v_ctx -> 'marcas' ->> 'tem_proposta')::boolean is not false then
    raise exception '8c: o "Fechado" sem a marca aceite_registrado: %', v_ctx -> 'marcas';
  end if;
  perform pg_temp.f5t_igual('8d trechos ({do_servico} dentro)', v_ctx ->> 'trechos_do_modelo',
    '["Fechado, ", "! Anotei a aprovação do orçamento das baterias de ", ". O Gustavo te passa a data por aqui."]');
  if v_ctx -> 'textos_do_cliente' is distinct from '["FRASE-F5-TEXTOS pode fazer o orçamento"]'::jsonb then
    raise exception '8e: textos do cliente (só os 30 dias antes de p_agora): %', v_ctx -> 'textos_do_cliente';
  end if;
  if (strpos(v_t, 'FRASE-F5') = 0) is not true then
    raise exception '8f: o texto do cliente subiu ao texto';
  end if;
  v_s := pg_temp.f5t_saida('orcamento', 'orc_vespera', 'retorno_orcamento', 'comercial', c_fone_ana, v_ana, 'agendada', c_t,
                           'orcamento:teste-f5-textos:8g');
  v_ctx := public._orcamento_contexto_do_validador(v_s, 'Oi, Ana! O orçamento das baterias vale até amanhã. Se quiser seguir ou ajustar algo, é só responder por aqui.',
                                                   '{"nome": "Ana", "validade": "amanhã"}', c_t);
  if (v_ctx -> 'marcas' ->> 'aceite_registrado')::boolean is not false
     or v_ctx -> 'datas_permitidas' is distinct from '["amanhã"]'::jsonb then
    raise exception '8g: a véspera: marcas ou datas erradas: %', v_ctx;
  end if;
  v_ctx := public._orcamento_contexto_do_validador(null, 'Oi, Ana! O orçamento vale até terça (19/01).', '{"nome": "Ana", "validade": "terça (19/01)"}', c_t);
  if v_ctx -> 'datas_permitidas' is distinct from '["19/01", "terça (19/01)"]'::jsonb
     or v_ctx -> 'textos_do_cliente' is distinct from '[]'::jsonb then
    raise exception '8h: sem saída (sem chave), datas ou textos errados: %', v_ctx;
  end if;

  -- ── 9. Grants: as funções novas fechadas (SECURITY DEFINER com search_path) e a varredura do orçamento pelo nome ──
  foreach v_par in array c_novas loop
    for v_rec in
      select p.oid, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v_par
    loop
      v_n_fun := v_n_fun + 1;
      if v_rec.prosecdef is not true or not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
        raise exception '9a: % não é SECURITY DEFINER com search_path', v_rec.nome;
      end if;
    end loop;
  end loop;
  if v_n_fun is distinct from 7 then
    raise exception '9b: achei % das 7 funções novas', v_n_fun;
  end if;
  if has_function_privilege('anon', 'public._cliente_ja_apresentada(uuid, text, date)', 'execute')
     or has_function_privilege('authenticated', 'public._cliente_ja_apresentada(uuid, text, date)', 'execute')
     or has_function_privilege('anon', 'public._retorno_tipo_curto(text)', 'execute')
     or has_function_privilege('authenticated', 'public._retorno_tipo_curto(text)', 'execute') then
    raise exception '9c: uma das geradas aberta a anon ou authenticated';
  end if;
  v_n_fun := 0;
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?orcamento'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_rec.oid, 'execute') then
      raise exception '9d: % aberta a anon', v_rec.nome;
    end if;
    if has_function_privilege('authenticated', v_rec.oid, 'execute') and v_rec.proname <> all (c_abertas) then
      raise exception '9e: % aberta a authenticated', v_rec.nome;
    end if;
    if v_rec.prosecdef and not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
      raise exception '9f: % é SECURITY DEFINER sem search_path', v_rec.nome;
    end if;
  end loop;
  if v_n_fun < 7 then
    raise exception '9g: a varredura das funções do orçamento achou só % (o filtro quebrou)', v_n_fun;
  end if;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_textos', true, '{}');
end
$textos$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
