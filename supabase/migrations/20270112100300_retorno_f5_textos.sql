-- Retorno rápido ao cliente, F5 (P4): os textos do orçamento (O01–O22), a legenda do PDF com a validade e o contexto do
-- validador. Nada liga aqui.
-- Gerada por script (scripts/gerar_f5.cjs textos): as funções novas vêm de scripts/f5_sql/p4_textos.sql, escritas à mão;
-- _cliente_ja_apresentada e _retorno_tipo_curto são geradas do corpo vigente (o do banco, achado pelo md5 do prosrc), e só os
-- trechos marcados -- F5 são novos.
--
-- 1. _orcamento_texto: o catálogo O01–O22, lista fechada de tipo/variante, modelo fixo, falta de dado = 22023. Dúvida 6: os
--    O01–O20 não saem antes da aprovação do dono (nada os chama com tudo desligado). O21 e O22 são só trechos já aprovados
--    (a legenda padrão de 20/10 e o "Ele vale até {validade}." da L01) e seguem o K6.
-- 2. _orcamento_do_servico: o {do_servico} da tabela fechada de _retorno_familia_rotulo, do texto do dono (descrição e linhas
--    do orçamento), nunca do cliente. Nenhuma família ou mais de 2: nulo (variante sem_servico).
-- 3. _orcamento_validade_texto: "hoje", "amanhã" ou "terça (15/12)"; data já passada: nulo (nenhuma data passada é afirmada).
-- 4. _orcamento_variante: padrao ou sem_servico, com _apresentacao quando a Claudia ainda não falou com o cliente; sem nome
--    utilizável (a regra da F1), 'sem_nome' (nenhum texto da F5 vai sem nome). Nos dados da nota, a variante sai das faltas.
-- 5. _orcamento_contexto_do_validador: as 9 chaves de ContextoDoValidador, mais a marca aceite_registrado (só no "Fechado").
-- 6. _orcamento_dia_envio: o dia do último envio ao cliente (mesma chave) antes da mensagem do aceite.
-- 7. _orcamento_legenda: O21 e O22 preenchidos e o contexto do validador (o número do ORÇ permitido). Quem chama é só
--    orcamento_validade_do_envio (P2), que devolve os três ao TS: o TS nunca chama a função "_" direto.
-- 8. Geradas: _cliente_ja_apresentada (a mensagem do orçamento enviada conta como apresentação) e _retorno_tipo_curto (os 5
--    tipos da F5).
--
-- Sem dado. Reverter: reaplicar _cliente_ja_apresentada de 20270105100300 e _retorno_tipo_curto de 20261208100300; depois,
-- drop function das sete funções _orcamento_* desta migration (orcamento_validade_do_envio, da P2, chama _orcamento_legenda).

-- ── 1. Os textos (O01 a O22) ────────────────────────────────────────────────────────────────────────────────────────────

-- Os campos: {nome} (_retorno_nome), {do_servico} (_orcamento_do_servico), {validade} (_orcamento_validade_texto),
-- {dia_envio} (dd/mm de _orcamento_dia_envio), {numero} (service_order_number), {documento} (CPF ou CNPJ). Quem monta os
-- dados é quem chama; aqui só a forma de cada campo é conferida.
create or replace function public._orcamento_texto(p_tipo text, p_variante text, p_dados jsonb)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_dia constant text := '^(hoje|amanhã|(segunda|terça|quarta|quinta|sexta|sábado|domingo) \([0-9]{2}/[0-9]{2}\))$';
  c_ddmm constant text := '^[0-9]{2}/[0-9]{2}$';
  c_numero constant text := '^(ORÇ|OS)-[0-9]{3,8}$';
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_modelo text;
  v_texto text;
  v_campo text;
  v_valor text;
begin
  v_modelo := case p_tipo || '/' || p_variante
    when 'orc_lembrete/padrao' then -- O01
      'Oi, {nome}! Conseguiu ver o orçamento {do_servico}? Se tiver alguma dúvida ou quiser ajustar algo, é só responder por aqui que eu passo ao Gustavo.'
    when 'orc_lembrete/padrao_apresentacao' then -- O02
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Conseguiu ver o orçamento {do_servico} que o Gustavo te mandou? Se tiver alguma dúvida ou quiser ajustar algo, é só responder por aqui que eu passo a ele.'
    when 'orc_lembrete/sem_servico' then -- O03
      'Oi, {nome}! Conseguiu ver o orçamento que o Gustavo te mandou? Se tiver alguma dúvida ou quiser ajustar algo, é só responder por aqui que eu passo a ele.'
    when 'orc_lembrete/sem_servico_apresentacao' then -- O04
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Conseguiu ver o orçamento que o Gustavo te mandou? Se tiver alguma dúvida ou quiser ajustar algo, é só responder por aqui que eu passo a ele.'
    when 'orc_vespera/padrao' then -- O05
      'Oi, {nome}! O orçamento {do_servico} vale até {validade}. Se quiser seguir ou ajustar algo, é só responder por aqui.'
    when 'orc_vespera/padrao_apresentacao' then -- O06
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. O orçamento {do_servico} que o Gustavo te mandou vale até {validade}. Se quiser seguir ou ajustar algo, é só responder por aqui.'
    when 'orc_vespera/sem_servico' then -- O07
      'Oi, {nome}! O orçamento que o Gustavo te mandou vale até {validade}. Se quiser seguir ou ajustar algo, é só responder por aqui.'
    when 'orc_vespera/sem_servico_apresentacao' then -- O08
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. O orçamento que o Gustavo te mandou vale até {validade}. Se quiser seguir ou ajustar algo, é só responder por aqui.'
    when 'orc_encerramento/padrao' then -- O09
      'Oi, {nome}! Como não tive retorno, vou encerrar por aqui o orçamento {do_servico}. Se quiser retomar, é só me chamar que o Gustavo atualiza para você.'
    when 'orc_encerramento/padrao_apresentacao' then -- O10
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Como não tive retorno sobre o orçamento {do_servico} que o Gustavo te mandou, vou encerrar por aqui. Se quiser retomar, é só me chamar que ele atualiza para você.'
    when 'orc_encerramento/sem_servico' then -- O11
      'Oi, {nome}! Como não tive retorno sobre o orçamento que o Gustavo te mandou, vou encerrar por aqui. Se quiser retomar, é só me chamar que ele atualiza para você.'
    when 'orc_encerramento/sem_servico_apresentacao' then -- O12
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Como não tive retorno sobre o orçamento que o Gustavo te mandou, vou encerrar por aqui. Se quiser retomar, é só me chamar que ele atualiza para você.'
    when 'orc_fechado/padrao' then -- O13
      'Fechado, {nome}! Anotei a aprovação do orçamento {do_servico} de {dia_envio}. O Gustavo te passa a data por aqui.'
    when 'orc_fechado/padrao_apresentacao' then -- O14
      'Fechado, {nome}! Aqui é a Claudia, assistente virtual da HBR. Anotei a aprovação do orçamento {do_servico} de {dia_envio}. O Gustavo te passa a data por aqui.'
    when 'orc_fechado/sem_servico' then -- O15
      'Fechado, {nome}! Anotei a aprovação do orçamento de {dia_envio}. O Gustavo te passa a data por aqui.'
    when 'orc_fechado/sem_servico_apresentacao' then -- O16
      'Fechado, {nome}! Aqui é a Claudia, assistente virtual da HBR. Anotei a aprovação do orçamento de {dia_envio}. O Gustavo te passa a data por aqui.'
    when 'orc_dados_nota/cpf_endereco' then -- O17
      '{nome}, para emitir a nota, me passa o CPF e o endereço completo, com CEP? Pode ser por aqui mesmo.'
    when 'orc_dados_nota/cnpj_endereco' then -- O18
      '{nome}, para emitir a nota, me passa o CNPJ e o endereço completo, com CEP? Pode ser por aqui mesmo.'
    when 'orc_dados_nota/documento' then -- O19
      '{nome}, para emitir a nota, me passa o {documento}? Pode ser por aqui mesmo.'
    when 'orc_dados_nota/endereco' then -- O20
      '{nome}, para emitir a nota, me passa o endereço completo, com CEP? Pode ser por aqui mesmo.'
    when 'orc_legenda/padrao' then -- O21
      'Segue o {numero}, conforme solicitado. Ele vale até {validade}. Qualquer dúvida, estamos à disposição.'
    when 'orc_legenda/linha' then -- O22
      'Ele vale até {validade}.'
  end;
  if v_modelo is null then
    raise exception 'texto F5: par desconhecido' using errcode = '22023';
  end if;

  v_texto := v_modelo;
  for v_campo in select distinct (regexp_matches(v_modelo, '\{([a-z_]+)\}', 'g'))[1] loop
    v_valor := nullif(btrim(d ->> v_campo), '');
    if v_valor is null
       or (v_campo = 'validade' and v_valor !~ c_dia)
       or (v_campo = 'dia_envio' and v_valor !~ c_ddmm)
       or (v_campo = 'numero' and v_valor !~ c_numero)
       or (v_campo = 'documento' and v_valor not in ('CPF', 'CNPJ')) then
      raise exception 'texto F5: campo % ausente ou inválido', v_campo using errcode = '22023';
    end if;
    v_texto := replace(v_texto, '{' || v_campo || '}', v_valor);
  end loop;
  return v_texto;
end;
$$;

comment on function public._orcamento_texto(text, text, jsonb) is
  'Retorno F5 (P4.1): os textos O01–O22 do orçamento (lembrete, véspera, encerramento, "Fechado", dados da nota, legenda do PDF). Lista fechada de tipo/variante, modelo fixo; campo ausente ou fora da forma ({validade}: hoje, amanhã ou "dia (dd/mm)"; {dia_envio}: dd/mm; {numero}: ORÇ-/OS- com 3 a 8 dígitos; {documento}: CPF ou CNPJ) = 22023.';

revoke all on function public._orcamento_texto(text, text, jsonb) from public, anon, authenticated;

-- ── 2. O {do_servico} ───────────────────────────────────────────────────────────────────────────────────────────────────

-- O texto de busca é do dono: a descrição do orçamento e os nomes das linhas de produto e de serviço (o mesmo de
-- retorno_parecidos, F3). Nunca lê mensagem do cliente.
create or replace function public._orcamento_do_servico(p_os uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select public._retorno_familia_rotulo(public._retorno_familias(public._retorno_busca(
           coalesce(so.problem_description, '') || ' ' || coalesce(l.nomes, '')))) ->> 'do_servico'
    from public.service_orders so
    left join lateral (
      select string_agg(x.nome, ' ') as nomes
        from (select coalesce(pr.name, '') as nome
                from public.service_order_parts p
                left join public.products pr on pr.id = p.product_id
               where p.service_order_id = so.id
              union all
              select coalesce(s.name_snapshot, '')
                from public.service_order_services s
               where s.service_order_id = so.id) x
    ) l on true
   where so.id = p_os;
$$;

comment on function public._orcamento_do_servico(uuid) is
  'Retorno F5 (P4.1): o {do_servico} do orçamento ("das baterias", "de energia solar e do inversor"), pela tabela fechada de _retorno_familia_rotulo sobre a descrição e as linhas (texto do dono). Nenhuma família, mais de 2 ou ordem que não existe: nulo.';

revoke all on function public._orcamento_do_servico(uuid) from public, anon, authenticated;

-- ── 3. A {validade} ─────────────────────────────────────────────────────────────────────────────────────────────────────

create or replace function public._orcamento_validade_texto(p_validade date, p_hoje date)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case when p_validade is null or p_hoje is null or p_validade < p_hoje then null
              else public._retorno_quando(p_validade, p_hoje) end;
$$;

comment on function public._orcamento_validade_texto(date, date) is
  'Retorno F5 (P4.1): a {validade} como o cliente lê, vista de p_hoje: hoje, amanhã ou "terça (15/12)" (_retorno_quando). Data anterior a p_hoje, ou nula: nulo (nenhuma data passada é afirmada ao cliente).';

revoke all on function public._orcamento_validade_texto(date, date) from public, anon, authenticated;

-- ── 4. A variante ───────────────────────────────────────────────────────────────────────────────────────────────────────

-- Cadência e "Fechado": padrao (com {do_servico}) ou sem_servico, com _apresentacao quando _cliente_ja_apresentada é falso
-- (o PDF mandado pelo dono não apresenta a Claudia). Dados da nota: pelas faltas (dados.faltas, ou as gravadas no aceite de
-- dados.aceite_id, rótulos de faltasParaNota): documento e endereço → cpf_endereco (cnpj_endereco para empresa); só um dos
-- dois → documento ou endereco ({documento} vem nos dados de quem chama); nada a pedir → nulo. Sem nome → 'sem_nome', que
-- _orcamento_texto não conhece (22023): a saída cai com sem_nome.
create or replace function public._orcamento_variante(p_tipo text, p_os uuid, p_client uuid, p_chave text, p_hoje date, p_dados jsonb)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_faltas text[];
  v_doc boolean;
  v_end boolean;
  v_empresa boolean;
  v_base text;
begin
  if p_tipo is null or p_tipo not in ('orc_lembrete', 'orc_vespera', 'orc_encerramento', 'orc_fechado', 'orc_dados_nota') then
    raise exception 'variante F5: tipo desconhecido' using errcode = '22023';
  end if;
  -- Nenhum texto da F5 vai sem nome (a regra da F1: o cadastro, nunca o perfil do WhatsApp).
  if public._retorno_nome(p_client) is null then
    return 'sem_nome';
  end if;

  if p_tipo = 'orc_dados_nota' then
    if jsonb_typeof(d -> 'faltas') = 'array' then
      v_faltas := array(select jsonb_array_elements_text(d -> 'faltas'));
    elsif coalesce(d ->> 'aceite_id', '') ~ c_uuid then
      select a.faltas_nota into v_faltas from public.orcamento_aceites a where a.id = (d ->> 'aceite_id')::uuid;
    end if;
    v_doc := coalesce(v_faltas && array['CPF/CNPJ', 'CPF/CNPJ incompleto'], false);
    v_end := coalesce(v_faltas && array['rua', 'bairro', 'cidade', 'UF', 'CEP', 'CEP incompleto'], false);
    select c.type = 'company' into v_empresa from public.clients c where c.id = p_client;
    return (case when v_doc and v_end then (case when v_empresa then 'cnpj_endereco' else 'cpf_endereco' end)
                 when v_doc then 'documento'
                 when v_end then 'endereco' end);
  end if;

  v_base := (case when public._orcamento_do_servico(p_os) is null then 'sem_servico' else 'padrao' end);
  return v_base || (case when public._cliente_ja_apresentada(p_client, p_chave, p_hoje) then '' else '_apresentacao' end);
end;
$$;

comment on function public._orcamento_variante(text, uuid, uuid, text, date, jsonb) is
  'Retorno F5 (P4.1): a variante do texto do orçamento. Cadência e orc_fechado: padrao ou sem_servico (sem {do_servico}), com _apresentacao quando a Claudia ainda não falou com o cliente. orc_dados_nota: cpf_endereco, cnpj_endereco (empresa), documento ou endereco, pelas faltas (dados.faltas ou orcamento_aceites.faltas_nota de dados.aceite_id); nada a pedir: nulo. Sem nome (_retorno_nome): sem_nome. Tipo fora da lista: 22023.';

revoke all on function public._orcamento_variante(text, uuid, uuid, text, date, jsonb) from public, anon, authenticated;

-- ── 5. O contexto do validador ──────────────────────────────────────────────────────────────────────────────────────────

-- As 9 chaves de ContextoDoValidador, no molde de _retorno_contexto_do_validador. datas: {validade} (e o dd/mm de dentro) e
-- {dia_envio} como saíram no texto; nome: {nome}; nomes_de_outros: os nomes curtos dos outros clientes do mesmo número (e os
-- do caso ambíguo, como a F1); os_permitidas vazio (nenhum texto da cadência, do aceite ou dos dados diz número);
-- textos_do_cliente: as recebidas da chave nos 30 dias antes de p_agora (só para o eco); trechos: o texto cortado em {nome},
-- {validade} e {dia_envio}, com o {do_servico} dentro do trecho (a regra da F3). aceite_registrado só no orc_fechado.
create or replace function public._orcamento_contexto_do_validador(p_saida uuid, p_texto text, p_dados jsonb, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_sep constant text := chr(31);
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_agora timestamptz := coalesce(p_agora, now());
  v_texto text := coalesce(p_texto, '');
  v_nome text := nullif(btrim(d ->> 'nome'), '');
  v_validade text := nullif(btrim(d ->> 'validade'), '');
  v_dia_envio text := nullif(btrim(d ->> 'dia_envio'), '');
  v_tipo text;
  v_chave text;
  v_client uuid;
  v_abertura uuid;
  v_datas text[];
  v_corte text;
  v_valor text;
  v_trechos text[];
  v_outros text[];
  v_cliente jsonb;
begin
  select s.tipo, s.chave, s.client_id, s.abertura_id into v_tipo, v_chave, v_client, v_abertura
    from public.retorno_saidas s where s.id = p_saida;
  v_tipo := coalesce(v_tipo, nullif(d ->> 'tipo', ''));
  v_chave := coalesce(v_chave, public._agenda_chave_telefone(d ->> 'chave'));
  if v_client is null and coalesce(d ->> 'client_id', '') ~ c_uuid then
    v_client := (d ->> 'client_id')::uuid;
  end if;

  v_datas := array(
    select distinct x
      from unnest(array[v_validade, (regexp_match(coalesce(v_validade, ''), '[0-9]{2}/[0-9]{2}'))[1], v_dia_envio]) as x
     where x is not null and x <> ''
     order by x);

  v_corte := v_texto;
  for v_valor in
    select x from unnest(array[v_nome, v_validade, v_dia_envio]) as x
     where x is not null and btrim(x) <> ''
     order by char_length(x) desc, x
  loop
    v_corte := replace(v_corte, v_valor, c_sep);
  end loop;
  v_trechos := array(select p from unnest(string_to_array(v_corte, c_sep)) as p where btrim(p) <> '');

  v_outros := array(
    select distinct n
      from (select public._agenda_nome_curto(coalesce(nullif(btrim(c.display_name), ''), c.name)) as n
              from public.clients c
             where v_chave is not null
               and c.id is distinct from v_client
               and (public._agenda_chave_telefone(c.whatsapp) = v_chave or public._agenda_chave_telefone(c.phone) = v_chave)
            union all
            select public._agenda_nome_curto(coalesce(nullif(btrim(c.display_name), ''), c.name))
              from public.retorno_aberturas a
              join public.clients c on c.id = any (a.clientes)
             where a.id = v_abertura and a.papel = 'cliente_ambiguo' and c.id is distinct from v_client) z
     where n is not null and btrim(n) <> ''
     order by n);

  select coalesce(jsonb_agg(w.body order by w.occurred_at, w.id), '[]'::jsonb) into v_cliente
    from public.whatsapp_messages w
   where v_chave is not null
     and w.direction = 'inbound'
     and public._agenda_chave_telefone(w.phone_normalized) = v_chave
     and w.occurred_at > v_agora - interval '30 days'
     and w.occurred_at <= v_agora
     and w.body is not null;

  return jsonb_build_object(
    'audiencia', 'cliente',
    'datas_permitidas', to_jsonb(coalesce(v_datas, '{}'::text[])),
    'horas_permitidas', '[]'::jsonb,
    'nome_permitido', v_nome,
    'nomes_de_outros', to_jsonb(coalesce(v_outros, '{}'::text[])),
    'os_permitidas', '[]'::jsonb,
    'textos_do_cliente', coalesce(v_cliente, '[]'::jsonb),
    'trechos_do_modelo', to_jsonb(coalesce(v_trechos, '{}'::text[])),
    'marcas', jsonb_build_object('tem_proposta', false, 'tem_topo', false, 'cliente_ouviu', false, 'conferida', false,
                                 'aceite_registrado', coalesce(v_tipo = 'orc_fechado', false)));
end;
$$;

comment on function public._orcamento_contexto_do_validador(uuid, text, jsonb, timestamptz) is
  'Retorno F5 (P4.1): o contexto do validador da saída do orçamento (as 9 chaves de ContextoDoValidador). datas = {validade} (e o dd/mm) e {dia_envio}; nome = {nome}; nomes_de_outros = os outros clientes do número (e do caso ambíguo); os_permitidas vazio; textos_do_cliente = as recebidas da chave nos 30 dias antes de p_agora (só o eco); trechos = o texto cortado em {nome}, {validade} e {dia_envio}; marcas falsas, com aceite_registrado só no orc_fechado.';

revoke all on function public._orcamento_contexto_do_validador(uuid, text, jsonb, timestamptz) from public, anon, authenticated;

-- ── 6. O dia do envio que o cliente aprovou ─────────────────────────────────────────────────────────────────────────────

create or replace function public._orcamento_dia_envio(p_os uuid, p_chave text, p_antes timestamptz)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select (max(e.em) at time zone 'America/Sao_Paulo')::date
    from public.orcamento_envios e
   where e.service_order_id = p_os
     and e.ao_cliente
     and e.chave = p_chave
     and e.em < p_antes;
$$;

comment on function public._orcamento_dia_envio(uuid, text, timestamptz) is
  'Retorno F5 (P4.1): o dia (Brasília) do último envio do orçamento ao cliente, na mesma chave, antes de p_antes (a mensagem do aceite): quem aprovou a versão reenviada vê a data dela. Sem envio: nulo.';

revoke all on function public._orcamento_dia_envio(uuid, text, timestamptz) from public, anon, authenticated;

-- ── 7. A legenda do PDF (O21 e O22) ─────────────────────────────────────────────────────────────────────────────────────

-- O21 = a legenda padrão de legendaDoPdf (20/10) com o "Ele vale até {validade}." da L01; O22 = só esse trecho, para ir
-- depois da frase do dono. O contexto: o número do ORÇ permitido, a {validade}, e O21 e O22 sem os campos. A data já
-- passada não tem {validade} (22023): quem chama só pede com a data de pé.
create or replace function public._orcamento_legenda(p_os uuid, p_validade date, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_sep constant text := chr(31);
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_numero text;
  v_validade text;
  v_legenda text;
  v_linha text;
  v_corte text;
  v_valor text;
  v_trechos text[];
begin
  select so.service_order_number into v_numero from public.service_orders so where so.id = p_os;
  v_validade := public._orcamento_validade_texto(p_validade, v_hoje);
  v_legenda := public._orcamento_texto('orc_legenda', 'padrao', jsonb_build_object('numero', v_numero, 'validade', v_validade));
  v_linha := public._orcamento_texto('orc_legenda', 'linha', jsonb_build_object('validade', v_validade));

  v_corte := v_legenda || c_sep || v_linha;
  for v_valor in select x from unnest(array[v_numero, v_validade]) as x order by char_length(x) desc, x loop
    v_corte := replace(v_corte, v_valor, c_sep);
  end loop;
  v_trechos := array(select p from unnest(string_to_array(v_corte, c_sep)) as p where btrim(p) <> '');

  return jsonb_build_object(
    'legenda', v_legenda,
    'linha', v_linha,
    'contexto', jsonb_build_object(
      'audiencia', 'cliente',
      'datas_permitidas', jsonb_build_array(v_validade),
      'horas_permitidas', '[]'::jsonb,
      'nome_permitido', null,
      'nomes_de_outros', '[]'::jsonb,
      'os_permitidas', jsonb_build_array(v_numero),
      'textos_do_cliente', '[]'::jsonb,
      'trechos_do_modelo', to_jsonb(coalesce(v_trechos, '{}'::text[])),
      'marcas', jsonb_build_object('tem_proposta', false, 'tem_topo', false, 'cliente_ouviu', false, 'conferida', false,
                                   'aceite_registrado', false)));
end;
$$;

comment on function public._orcamento_legenda(uuid, date, timestamptz) is
  'Retorno F5 (P4.1, K6): {legenda, linha, contexto} da legenda do PDF do orçamento. legenda = O21 ("Segue o ORÇ-00151, conforme solicitado. Ele vale até terça (15/12). Qualquer dúvida, estamos à disposição."), linha = O22; contexto do validador com o número permitido. Data anterior a hoje (Brasília de p_agora): 22023. Só orcamento_validade_do_envio chama.';

revoke all on function public._orcamento_legenda(uuid, date, timestamptz) from public, anon, authenticated;

-- ── 8. Gerado do corpo vigente, com os trechos -- F5 ────────────────────────────────────────────────────────────────────

create or replace function public._cliente_ja_apresentada(p_client_id uuid, p_chave text, p_hoje date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with j as (
    select (p_hoje::timestamp at time zone 'America/Sao_Paulo')
             - coalesce((public._retorno_cfg()).apresentacao_intervalo, interval '365 days') as desde,
           ((p_hoje + 1)::timestamp at time zone 'America/Sao_Paulo') as ate
  )
  select exists (select 1 from public.agenda_cliente_mensagens m, j
                  where p_client_id is not null
                    and m.client_id = p_client_id
                    and m.enviada_em > j.desde and m.enviada_em < j.ate)
      or exists (select 1 from public.retorno_saidas s, j
                  where s.emissor = 'retorno'
                    and s.estado = 'enviada'
                    and s.tipo not in ('acorde', 'cadastro_provisorio', 'fila')
                    and (s.client_id = p_client_id or s.chave = p_chave)
                    and s.enviada_em > j.desde and s.enviada_em < j.ate)
      -- F3 (P4): a legenda com apresentação conta como apresentação; o PDF não passa por retorno_saidas nem por agenda_cliente_mensagens.
      or exists (select 1 from public.retorno_previa p, j
                  where p.pdf_em > j.desde and p.pdf_em < j.ate
                    and (p.client_id = p_client_id or p.chave = p_chave))
      -- F4 (P4): o aviso ao cliente final (Q01–Q05) enviado conta como apresentação; a incerta não conta.
      or exists (select 1 from public.retorno_saidas s, j
                  where s.emissor = 'parceiro'
                    and s.tipo = 'parceiro_aviso_cliente'
                    and s.estado = 'enviada'
                    and (s.client_id = p_client_id or s.chave = p_chave)
                    and s.enviada_em > j.desde and s.enviada_em < j.ate)
      -- F5 (P4): a mensagem do orçamento enviada (lembrete, véspera, encerramento, "Fechado", dados) conta como apresentação;
      -- a sombra e a incerta não contam.
      or exists (select 1 from public.retorno_saidas s, j
                  where s.emissor = 'orcamento'
                    and s.estado = 'enviada'
                    and (s.client_id = p_client_id or s.chave = p_chave)
                    and s.enviada_em > j.desde and s.enviada_em < j.ate);
$$;
revoke all on function public._cliente_ja_apresentada(uuid, text, date) from public, anon, authenticated;

create or replace function public._retorno_tipo_curto(p_tipo text)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_tipo
    when 'modelo_aguarda_peca' then 'aguardando peça'
    when 'modelo_peca_chegou' then 'peça chegou'
    when 'modelo_pronto' then 'pronto'
    when 'modelo_em_servico' then 'em serviço'
    when 'modelo_liberado' then 'liberado'
    when 'modelo_retirada_nao' then 'retirada ainda não'
    when 'modelo_ver_no_local' then 'ver no local'   -- F3
    when 'orc_lembrete' then 'lembrete do orçamento'           -- F5 (P4)
    when 'orc_vespera' then 'véspera do orçamento'             -- F5 (P4)
    when 'orc_encerramento' then 'encerramento do orçamento'   -- F5 (P4)
    when 'orc_fechado' then 'fechado do orçamento'             -- F5 (P4)
    when 'orc_dados_nota' then 'dados da nota'                 -- F5 (P4)
  end;
$$;
revoke all on function public._retorno_tipo_curto(text) from public, anon, authenticated;
