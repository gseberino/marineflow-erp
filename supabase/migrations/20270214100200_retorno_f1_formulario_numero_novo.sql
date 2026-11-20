-- Retorno rápido ao cliente, F1: resposta do dono ao cartão rr-f1-11 (20/11/2026). Ele não escolheu opção; escreveu: "quando é um
-- novo contato, sem associação com os cadastros do sistema pelo numero, voce pede os dados para realizar o cadastro do cliente,
-- eu tenho uma lista pronta que esta salva como atalho de mensagens rapidas do whatsapp". Lido como: o número sem cadastro que
-- pede serviço, sem exigir o veículo, recebe o recibo e, logo depois, o formulário dele, exato. Gerada por
-- scripts/gerar_formulario.cjs; as quatro funções vigentes saem do corpo de PRODUÇÃO, com trocas conferidas.
--
-- 1. _retorno_numero_novo_ligado() (nova): a resposta a número novo está ligada (recibo_numero_novo em tipos_ligados). É o
--    interruptor de sempre: desligado, a regra do pedido é a de hoje, byte a byte.
-- 2. _retorno_pedido_de_servico: com o interruptor ligado, pedido = site ou (serviço e pedido), sem o veículo. Vendedor nunca.
-- 3. _retorno_texto: T36, coleta_numero_novo/formulario = o texto do dono, fixo do banco, sem IA e sem campo.
-- 4. _retorno_triar: com o interruptor ligado, o recibo do número novo agenda junto o formulário (coleta_numero_novo,
--    variante formulario, a mesma vaga da coleta), 1 minuto depois; uma vez por contato (chave que já recebeu um, enviado ou incerto, não recebe outro). A
--    resposta é lida por _retorno_formulario_lido: o "Nome: ..." vira o nome do cadastro provisório (antes só valia a
--    resposta de 1 ou 2 palavras ao "Como posso chamar você?"), o CPF vira o documento (o cadastro acha duplicado por ele) e
--    os campos ficam literais em coleta.formulario.
-- 5. retorno_pegar: com o formulário a seguir, o recibo sai sem pergunta (sem_pergunta, T17). O formulário espera o recibo
--    ser decidido; recibo que não saiu leva o formulário junto; chave que já recebeu um formulário não recebe outro.
--    Equipe, fornecedor e vendedor nunca chegam aqui: a identificação de sempre (quem_escreve, papel numero_novo, regra 8
--    "vendedor" da triagem).
-- 6. _retorno_formulario_lido(texto) (nova, IMMUTABLE): lê "Rótulo: valor" linha a linha; só vale com 3 ou mais rótulos do
--    formulário. Nome sem número nem @; CPF só com os dígitos.
--
-- O validador da edge (validador.ts) aceita o formulário acima do limite de 5 linhas só quando o texto é exatamente este.
-- NADA LIGA: recibo_numero_novo, coleta_numero_novo e cadastro_provisorio seguem fora de tipos_ligados. Com eles fora, a
-- regra do pedido e a triagem são as de hoje, e nenhum formulário nasce (nem em sombra). A única mudança visível sem ligar é a
-- leitura do formulário respondido, que só existe se ele foi enviado. Ligar pede OK nomeado do dono: tipos_ligados +=
-- recibo_numero_novo e coleta_numero_novo juntos (o formulário é uma coleta; sem ela, o recibo sai e o formulário fica em
-- sombra), e cadastro_provisorio se ele quiser o cadastro provisório automático.
-- Reverter: reaplicar _retorno_pedido_de_servico (20261116100300), _retorno_texto (20261116100400), _retorno_triar
-- (20270105100100) e retorno_pegar (20270112100400); drop function public._retorno_formulario_lido(text),
-- public._retorno_numero_novo_ligado().

-- ── 1. As novas ────────────────────────────────────────────────────────────────────────────────────────────────────────

create or replace function public._retorno_numero_novo_ligado()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce('recibo_numero_novo' = any ((public._retorno_cfg()).tipos_ligados), false);
$$;

comment on function public._retorno_numero_novo_ligado() is
  'Retorno F1 (rr-f1-11, 20/11/2026): a resposta a número novo está ligada (recibo_numero_novo em tipos_ligados). Com ela, o pedido de serviço do número novo não exige o veículo.';

revoke all on function public._retorno_numero_novo_ligado() from public, anon, authenticated;

create or replace function public._retorno_formulario_lido(p_texto text)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_linha text;
  v_m text[];
  v_campo text;
  v_valor text;
  v_r jsonb := '{}'::jsonb;
  v_rotulos integer := 0;
  v_nome text;
  v_cpf text;
begin
  if p_texto is null or strpos(p_texto, ':') = 0 then
    return null;
  end if;
  foreach v_linha in array regexp_split_to_array(p_texto, E'\r?\n') loop
    -- O negrito do WhatsApp pode vir em volta do rótulo inteiro, dois-pontos inclusive (*Nome:*): os asteriscos não são valor.
    v_m := regexp_match(v_linha, '^\s*[*_]*([^:*_]{2,40}?)[*_]*\s*:[*_]*\s*(.*?)[*_]*\s*$');
    continue when v_m is null;
    v_campo := case public._retorno_busca(v_m[1])
      when 'nome' then 'nome' when 'nome completo' then 'nome'
      when 'cpf' then 'cpf' when 'cpf cnpj' then 'cpf'
      when 'data nasc' then 'nascimento' when 'data de nascimento' then 'nascimento' when 'nascimento' then 'nascimento'
      when 'cel whats' then 'celular' when 'celular' then 'celular' when 'whatsapp' then 'celular'
      when 'endereco' then 'endereco' when 'cep' then 'cep' when 'email' then 'email' when 'e mail' then 'email'
      when 'local fixo lancha veiculo' then 'local' when 'nome embarcacao' then 'embarcacao' when 'fabricante' then 'fabricante'
      when 'ano' then 'ano' when 'modelo' then 'modelo' when 'tamanho' then 'tamanho'
      when 'placa veiculo' then 'placa' when 'placa' then 'placa'
    end;
    continue when v_campo is null;
    v_rotulos := v_rotulos + 1;
    v_valor := left(btrim(coalesce(v_m[2], '')), 200);
    if v_valor <> '' and not (v_r ? v_campo) then
      v_r := v_r || jsonb_build_object(v_campo, v_valor);
    end if;
  end loop;
  if v_rotulos < 3 then
    return null;   -- "Nome: Ana" solto numa conversa não é o formulário
  end if;
  v_nome := v_r ->> 'nome';
  if v_nome is not null and (v_nome ~ '[0-9@]' or v_nome !~ '[[:alpha:]].*[[:alpha:]]' or char_length(v_nome) > 80) then
    v_r := v_r - 'nome';
  end if;
  if v_r ? 'cpf' then
    v_cpf := regexp_replace(v_r ->> 'cpf', '[^0-9]', '', 'g');
    v_r := case when v_cpf = '' then v_r - 'cpf' else v_r || jsonb_build_object('cpf', v_cpf) end;
  end if;
  return v_r || jsonb_build_object('rotulos', v_rotulos);
end;
$$;

comment on function public._retorno_formulario_lido(text) is
  'Retorno F1 (rr-f1-11): o formulário de cadastro do dono respondido ("Nome: ...", "CPF: ..."), literal, campo a campo (nome, cpf, nascimento, celular, endereco, cep, email, local, embarcacao, fabricante, ano, modelo, tamanho, placa) e rotulos. Nulo com menos de 3 rótulos do formulário. Nome com número ou @ sai; CPF só com os dígitos. Sem IA.';

revoke all on function public._retorno_formulario_lido(text) from public, anon, authenticated;

-- ── 2. Gerado do corpo vigente em produção (pg_get_functiondef), com os trechos rr-f1-11 ──────────────────────────────

create or replace function public._retorno_pedido_de_servico(p_chave text, p_desde timestamp with time zone, p_ate timestamp with time zone, p_nome text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
as $$
  with msgs as (
    select m.id, m.body, m.occurred_at, public._retorno_hora_real(m) as real,
           public._retorno_sinais(m.body, p_nome) as s
      from public.whatsapp_messages m
     where public._agenda_chave_telefone(m.phone_normalized) = p_chave
       and m.direction = 'inbound'
       and m.occurred_at <= p_ate
       and m.occurred_at >= p_desde - interval '10 minutes'
       and public._retorno_hora_real(m) between p_desde and least(p_ate, p_desde + interval '24 hours')
  ), soma as (
    select coalesce(bool_or((s ->> 'servico')::boolean), false) as servico,
           coalesce(bool_and((s ->> 'servico_generico')::boolean or not (s ->> 'servico')::boolean), true) as so_generico,
           coalesce(bool_or((s ->> 'bem')::boolean), false) as bem,
           (array_agg(s ->> 'bem_palavra' order by real, occurred_at, id) filter (where s ->> 'bem_palavra' is not null))[1] as bem_palavra,
           (array_agg(s ->> 'modelo' order by real, occurred_at, id) filter (where s ->> 'modelo' is not null))[1] as modelo,
           (array_agg(s ->> 'ano' order by real, occurred_at, id) filter (where s ->> 'ano' is not null))[1] as ano,
           coalesce(bool_or((s ->> 'pedido')::boolean), false) as pedido,
           coalesce(bool_or((s ->> 'vendedor')::boolean), false) as vendedor,
           coalesce(bool_or((s ->> 'site')::boolean), false) as site,
           (array_agg(left(body, 300) order by real, occurred_at, id) filter (where (s ->> 'servico')::boolean))[1] as pedido_literal,
           coalesce(jsonb_agg(id order by real, occurred_at, id), '[]'::jsonb) as ids
      from msgs
  )
  select jsonb_build_object(
    -- rr-f1-11 (20/11/2026): com a resposta a número novo ligada (recibo_numero_novo), o veículo não é exigido.
    'pedido', (soma.site or (soma.servico and (soma.bem or public._retorno_numero_novo_ligado()) and soma.pedido)) and not soma.vendedor,
    'servico', soma.servico,
    'servico_generico', soma.servico and soma.so_generico,
    'bem', soma.bem,
    'bem_palavra', soma.bem_palavra,
    'modelo', soma.modelo,
    'ano', soma.ano,
    'vendedor', soma.vendedor,
    'site', soma.site,
    'pedido_literal', soma.pedido_literal,
    'msgs', soma.ids)
  from soma;
$$;

create or replace function public._retorno_texto(p_tipo text, p_variante text, p_dados jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
as $$
declare
  c_dia constant text := '^(hoje|amanhã|(segunda|terça|quarta|quinta|sexta|sábado|domingo) \([0-9]{2}/[0-9]{2}\))$';
  c_hora constant text := '^[0-9]{1,2}h$|^[0-9]{2}:[0-9]{2}$';
  c_risco constant text := 'Se houver fogo, fumaça ou água entrando, ligue 193 (Bombeiros).';   -- L01
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_modelo text;
  v_texto text;
  v_campo text;
  v_valor text;
  v_parte text;
  v_ok boolean;
begin
  v_modelo := case p_tipo || '/' || p_variante
    when 'recibo_cliente/padrao' then -- T01
      'Oi, {nome}! Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/padrao_apresentacao' then -- T02
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/sem_nome' then -- T03
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/outro_dia' then -- T04
      'Oi, {nome}! Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.'
    when 'recibo_cliente/outro_dia_apresentacao' then -- T05
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.'
    when 'recibo_cliente/outro_dia_sem_nome' then -- T06
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.'
    when 'recibo_cliente/manha' then -- T07
      'Bom dia, {nome}! Vi sua mensagem {de_quando} e já passei ao Gustavo. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/manha_apresentacao' then -- T07a
      'Bom dia, {nome}! Aqui é a Claudia, assistente virtual da HBR. Vi sua mensagem {de_quando} e já passei ao Gustavo. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/manha_outro_dia' then -- T08
      'Bom dia, {nome}! Vi sua mensagem {de_quando} e já passei ao Gustavo. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/manha_outro_dia_apresentacao' then -- T08a
      'Bom dia, {nome}! Aqui é a Claudia, assistente virtual da HBR. Vi sua mensagem {de_quando} e já passei ao Gustavo. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/manha_sem_nome' then -- T09
      'Bom dia! Aqui é a Claudia, assistente virtual da HBR. Vi sua mensagem {de_quando} e já passei ao Gustavo. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/fora_ate' then -- T10
      'Oi, {nome}! O Gustavo está fora até {quando}, mas sua mensagem já está com ele. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/fora_ate_apresentacao' then -- T10a
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. O Gustavo está fora até {quando}, mas sua mensagem já está com ele. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/fora_ate_sem_nome' then -- T11
      'Olá! Aqui é a Claudia, assistente virtual da HBR. O Gustavo está fora até {quando}, mas sua mensagem já está com ele. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/volta' then -- T12
      'Oi, {nome}! Sua mensagem de {dia_msg} às {hora_msg} só chegou para nós agora. Desculpe a demora. Já passei ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/volta_apresentacao' then -- T12a
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Sua mensagem de {dia_msg} às {hora_msg} só chegou para nós agora. Desculpe a demora. Já passei ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/volta_queda' then -- T13
      'Oi, {nome}! Nosso WhatsApp ficou fora do ar por um tempo, e sua mensagem de {dia_msg} às {hora_msg} só chegou agora. Desculpe a demora. Já passei ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/volta_queda_apresentacao' then -- T13a
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Nosso WhatsApp ficou fora do ar por um tempo, e sua mensagem de {dia_msg} às {hora_msg} só chegou agora. Desculpe a demora. Já passei ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_ambiguo/padrao' then -- T14
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_numero_novo/pergunta_necessidade' then -- T15
      '{cumprimento}! Aqui é a Claudia, assistente virtual da HBR. Já passei seu pedido ao Gustavo, que cuida dos orçamentos, e ele retorna para você {quando_fala}. Para adiantar, pode me contar o que precisa resolver ou instalar? Pode ser por áudio.'
    when 'recibo_numero_novo/pergunta_modelo' then -- T16
      '{cumprimento}! Aqui é a Claudia, assistente virtual da HBR. Já passei seu pedido ao Gustavo, que cuida dos orçamentos, e ele retorna para você {quando_fala}. Para adiantar, qual é o modelo e o ano {do_bem}?'
    when 'recibo_numero_novo/sem_pergunta' then -- T17
      '{cumprimento}! Aqui é a Claudia, assistente virtual da HBR. Já passei seu pedido ao Gustavo, que cuida dos orçamentos, e ele retorna para você {quando_fala}.'
    when 'coleta_numero_novo/nome' then -- T18
      'Obrigada! Já passei ao Gustavo. Como posso chamar você?'
    when 'coleta_numero_novo/formulario' then -- T36 (rr-f1-11): o formulário do dono, exato, sem campo
      E'Dados para preenchimento do Orçamento / Ordem de Serviço:\n\nNome:\nCPF:\nData Nasc.:\nCel/Whats:\nEndereço:\nCEP:\nEmail:\nLocal fixo Lancha/Veículo:\nNome (Embarcação):\nFabricante:\nAno:\nModelo:\nTamanho:\nPlaca (Veículo):\n\nÉ muito importante ter o máximo de informações preenchidas.'
    when 'saudacao_numero_novo/padrao' then -- T19
      '{cumprimento}! Aqui é a Claudia, assistente virtual da HBR. Em que posso ajudar? Se preferir, pode mandar um áudio.'
    when 'adiamento/com_nome' then -- T20
      '{nome}, o Gustavo ainda não conseguiu retornar, mas seu pedido está com ele e a resposta sai ainda hoje. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.'
    when 'adiamento/sem_nome' then -- T21
      'O Gustavo ainda não conseguiu retornar, mas seu pedido está com ele e a resposta sai ainda hoje. Se for urgente, é só responder "urgente" que eu aviso o Gustavo na hora.'
    when 'fim_do_dia/com_nome' then -- T22
      '{nome}, o Gustavo não conseguiu retornar hoje, peço desculpas. Seu pedido é o primeiro da lista dele {quando_lista} cedo.'
    when 'fim_do_dia/sem_nome' then -- T23
      'O Gustavo não conseguiu retornar hoje, peço desculpas. Seu pedido é o primeiro da lista dele {quando_lista} cedo.'
    when 'urgente/acorde' then -- T24
      'Avisei o Gustavo agora mesmo, {nome}.'
    when 'urgente/acorde_sem_nome' then -- T24a
      'Avisei o Gustavo agora mesmo.'
    when 'urgente/sem_acorde' then -- T25
      'Anotei como urgente, {nome}. O Gustavo vê {quando_lista} cedo, antes de tudo.'
    when 'urgente/sem_acorde_sem_nome' then -- T26
      'Anotei como urgente. O Gustavo vê {quando_lista} cedo, antes de tudo.'
    when 'parar/com_nome' then -- T27
      'Combinado, {nome}. Não envio mais mensagens automáticas. Quando precisar, é só escrever.'
    when 'parar/sem_nome' then -- T28
      'Combinado. Não envio mais mensagens automáticas. Quando precisar, é só escrever.'
  end;
  if v_modelo is null then
    raise exception using errcode = '22023',
      message = format('retorno_texto: modelo desconhecido %s/%s', coalesce(p_tipo, '(nenhum)'), coalesce(p_variante, '(nenhuma)'));
  end if;

  -- O adiamento diz "ainda hoje" porque há um 2º prazo no mesmo dia: sem a hora dele, não há o que prometer.
  if p_tipo = 'adiamento' then
    v_valor := btrim(d ->> 'hora');
    if coalesce(v_valor, '') = '' then
      raise exception using errcode = '22023', message = 'retorno_texto: falta hora';
    end if;
    if v_valor !~ c_hora then
      raise exception using errcode = '22023', message = 'retorno_texto: valor fora da lista em hora';
    end if;
  end if;

  -- Cada {campo} do modelo, na ordem em que aparece: presente, não vazio e dentro da lista fechada.
  -- Nenhum valor aceito tem chave ({ ou }), então a troca de um campo nunca cria outro campo.
  v_texto := v_modelo;
  for v_campo in
    select x.m[1] from regexp_matches(v_modelo, '\{([a-z_]+)\}', 'g') with ordinality as x(m, n)
     group by x.m[1] order by min(x.n)
  loop
    -- {quando_fala} sai de quando + hora, que passam pela mesma conferência dos outros campos.
    if v_campo = 'quando_fala' then
      foreach v_parte in array array['quando', 'hora'] loop
        v_valor := btrim(d ->> v_parte);
        if coalesce(v_valor, '') = '' then
          raise exception using errcode = '22023', message = 'retorno_texto: falta ' || v_parte;
        end if;
        if v_valor !~ (case v_parte when 'quando' then c_dia else c_hora end) then
          raise exception using errcode = '22023', message = 'retorno_texto: valor fora da lista em ' || v_parte;
        end if;
      end loop;
      v_valor := public._retorno_quando_fala(btrim(d ->> 'quando'), btrim(d ->> 'hora'));
      if v_valor is null then
        raise exception using errcode = '22023', message = 'retorno_texto: valor fora da lista em quando';
      end if;
      v_texto := replace(v_texto, '{quando_fala}', v_valor);
      continue;
    end if;
    v_valor := btrim(d ->> v_campo);
    if coalesce(v_valor, '') = '' then
      raise exception using errcode = '22023', message = 'retorno_texto: falta ' || v_campo;
    end if;
    v_ok := case v_campo
      when 'cumprimento' then v_valor in ('Bom dia', 'Boa tarde', 'Boa noite')
      when 'de_quando' then v_valor in ('de ontem à noite', 'desta madrugada')
      when 'quando' then v_valor ~ c_dia
      when 'quando_lista' then v_valor ~ c_dia
      when 'dia_msg' then v_valor ~ c_dia
      when 'hora' then v_valor ~ c_hora
      when 'hora_msg' then v_valor ~ c_hora
      when 'nome' then char_length(v_valor) between 1 and 40 and v_valor !~ '[0-9]' and v_valor !~ '[[:cntrl:]{}]'
      when 'do_bem' then v_valor ~ '^d[oa] [a-záéíóúâêôãõç ]{2,20}$'
      else false
    end;
    if not coalesce(v_ok, false) then
      raise exception using errcode = '22023', message = 'retorno_texto: valor fora da lista em ' || v_campo;
    end if;
    v_texto := replace(v_texto, '{' || v_campo || '}', v_valor);
  end loop;

  -- A linha de risco (B.3) só nos recibos.
  if p_tipo in ('recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo') and d ->> 'risco' = 'true' then
    v_texto := v_texto || E'\n' || c_risco;
  end if;
  return v_texto;
end;
$$;

create or replace function public._retorno_triar(p_abertura uuid, p_agora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
as $$
declare
  -- mensagens que não são conversa: não dão sinal ao caso (robô, figurinha, reação, grupo)
  c_fora_da_conversa constant text[] := array['robo', 'figurinha_ou_reacao', 'nao_e_conversa'];
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  c_decididas constant text[] := array['sombra', 'enviada', 'incerta'];
  -- a lista de serviço de _retorno_sinais (P2, 20261116100300), para a coleta dizer as palavras achadas
  c_re_servico constant text :=
    '\y(orcamento|orcamentos|orcar|instalar|instalacao|instalacoes|trocar|troca|bateria|baterias|inversor|inversores|placa solar|placas solares|painel solar|paineis solares|energia solar|gerador|eletrica|eletrico|ar condicionado|bomba|carregador|tomada|tomadas|chicote)\y';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_agora timestamptz := coalesce(p_agora, now());
  v_ab public.retorno_aberturas;
  v_ult public.retorno_mensagens;          -- a mensagem que disparou: a última do caso até agora
  v_sinais jsonb;
  v_n_pede integer;
  v_n_pede_livre integer;
  v_n_pede_saudacao integer;
  v_tem_robo boolean;
  v_tem_vendedor boolean;
  v_tem_audio boolean;
  v_tem_parar boolean;                     -- alguma mensagem do caso é PARAR (exato)
  v_tem_parar_largo boolean;               -- alguma mensagem do caso é PARAR por extenso
  v_opt_out boolean;                       -- o opt-out da chave está gravado (até agora)
  v_insistencias integer;
  v_insiste_acorde uuid[];                 -- as mensagens da 2ª insistência em diante (ganham acorde)
  v_vencido boolean;
  v_canal text;
  v_lead_nome text;
  v_desde timestamptz;
  v_pd jsonb;
  v_pedido boolean := false;
  v_prometido timestamptz;
  v_nivel text;
  v_motivo text;
  v_tipo text;
  v_intencao text;
  v_risco boolean;
  v_passagem boolean;
  v_vencida_desde timestamptz;
  v_dono_ativo boolean;
  v_carencia interval;
  v_enviar timestamptz;
  v_recibo public.retorno_saidas;
  v_saudacao public.retorno_saidas;
  v_coleta_saida public.retorno_saidas;
  v_nome text;
  v_coleta jsonb;
  v_form jsonb;            -- rr-f1-11: o formulário respondido
  v_servicos text;
  v_tipo_bem text;
  v_modelo text;
  v_saida_id uuid;
  r record;
begin
  -- Sem a linha de configuração ou com o retorno desligado: nada (falha fecha), sem mexer em nada.
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return jsonb_build_object('abertura_id', p_abertura, 'papel', null, 'nivel', 'nada', 'motivo', 'desligado',
                              'tipo_recibo', null, 'estado', null, 'modo', null, 'saida_id', null);
  end if;

  select * into v_ab from public.retorno_aberturas ab where ab.id = p_abertura for update;
  if not found then
    return jsonb_build_object('abertura_id', p_abertura, 'papel', null, 'nivel', 'nada', 'motivo', 'sem_caso',
                              'tipo_recibo', null, 'estado', null, 'modo', null, 'saida_id', null);
  end if;

  -- F4 (P2): o caso do parceiro tem triagem própria, que repete o "caso fechado não muda".
  if v_ab.papel = 'parceiro' then
    return public._parceiro_triar(p_abertura, p_agora);
  end if;

  -- Caso fechado não muda mais: devolve como está.
  if v_ab.estado = 'fechada' then
    select s.id into v_saida_id from public.retorno_saidas s
     where s.dedupe_key in ('retorno:' || v_ab.id || ':recibo', 'retorno:' || v_ab.id || ':saudacao')
     order by (s.dedupe_key like '%:recibo') desc limit 1;
    return jsonb_build_object('abertura_id', v_ab.id, 'papel', v_ab.papel, 'nivel', v_ab.nivel, 'motivo', v_ab.motivo,
                              'tipo_recibo', v_ab.tipo_recibo, 'estado', v_ab.estado, 'modo', v_ab.modo,
                              'saida_id', v_saida_id);
  end if;

  -- ── As mensagens do caso gravadas até agora ──
  select count(*) filter (where rm.pede_resposta),
         count(*) filter (where rm.pede_resposta and not rm.consumida),
         count(*) filter (where rm.pede_resposta and coalesce((rm.sinais ->> 'saudacao')::boolean, false)),
         coalesce(bool_or(rm.pede_motivo = 'robo'), false),
         coalesce(bool_or(coalesce((rm.sinais ->> 'vendedor')::boolean, false)), false),
         coalesce(bool_or(rm.audio_pendente), false),
         coalesce(bool_or(coalesce((rm.sinais ->> 'parar')::boolean, false)), false),
         coalesce(bool_or(coalesce((rm.sinais ->> 'parar_largo')::boolean, false)), false)
    into v_n_pede, v_n_pede_livre, v_n_pede_saudacao, v_tem_robo, v_tem_vendedor, v_tem_audio,
         v_tem_parar, v_tem_parar_largo
    from public.retorno_mensagens rm
   where rm.abertura_id = v_ab.id
     and rm.gravada_em <= v_agora;

  select * into v_ult from public.retorno_mensagens rm
   where rm.abertura_id = v_ab.id and rm.gravada_em <= v_agora
   order by rm.recebida_em desc, rm.gravada_em desc, rm.whatsapp_message_id desc
   limit 1;

  -- As insistências, do caso inteiro, a cada triagem (nunca somadas na chegada): o par seguido de mensagens
  -- que PEDEM resposta, a 2ª insistencia_apos ou mais depois da 1ª, sem saída humana entre as duas (só as
  -- gravadas até agora). A cópia que o robô revelado deixou de pedir e o '[audio]' transcrito que não pede
  -- saem da conta sozinhos. Ganha acorde a 2ª insistência em diante (a que leva a conta a 2, e cada nova
  -- depois dela); a mensagem que chega 1 min depois não é insistência e não ganha.
  select count(*) filter (where i.insiste),
         coalesce(array_agg(i.msg order by i.ordem) filter (where i.insiste and i.n_insiste >= 2), '{}'::uuid[])
    into v_insistencias, v_insiste_acorde
    from (select p.msg, p.ordem, p.insiste,
                 sum(case when p.insiste then 1 else 0 end) over (order by p.ordem) as n_insiste
            from (select q.msg, q.ordem,
                         q.ant is not null
                         and q.recebida_em - q.ant >= v_cfg.insistencia_apos
                         and not exists (select 1 from public.whatsapp_messages o
                                          where public._agenda_chave_telefone(o.phone_normalized) = v_ab.chave
                                            and o.direction = 'outbound'
                                            and o.occurred_at <= v_agora
                                            and o.occurred_at >= q.ant
                                            and public._retorno_hora_real(o) > q.ant
                                            and public._retorno_hora_real(o) <= q.recebida_em
                                            and coalesce(o.saida_humana,
                                                         public._saida_e_humana(o.direction, o.raw_payload, o.sent_by)))
                           as insiste
                    from (select rm.whatsapp_message_id as msg, rm.recebida_em,
                                 row_number() over w as ordem,
                                 lag(rm.recebida_em) over w as ant
                            from public.retorno_mensagens rm
                           where rm.abertura_id = v_ab.id
                             and rm.pede_resposta
                             and rm.gravada_em <= v_agora
                          window w as (order by rm.recebida_em, rm.gravada_em, rm.whatsapp_message_id)) q) p) i;

  -- O caso vencido: o vigia já o marcou, ou a promessa do dono que o relógio adotou passou sem resposta de
  -- conteúdo (o vigia marca no minuto seguinte; a mensagem que chega antes não pode ganhar recibo novo, e o
  -- relógio da promessa fica para o vigia ver).
  v_vencido := v_ab.estado = 'vencida'
               or coalesce(v_ab.prometido_fonte = 'dono' and v_ab.prometido_ate <= v_agora and v_ab.cumprida_em is null,
                           false);

  -- Os sinais do caso: OU dos booleanos e o 1º valor dos textos (bem_palavra, modelo, ano), só das
  -- mensagens de conversa.
  select coalesce(jsonb_object_agg(x.chave_sinal, x.valor), '{}'::jsonb)
    into v_sinais
    from (select e.key as chave_sinal,
                 case when bool_and(jsonb_typeof(e.value) = 'boolean')
                      then to_jsonb(bool_or(e.value = 'true'::jsonb))
                      else (array_agg(e.value order by rm.recebida_em, rm.gravada_em, rm.whatsapp_message_id)
                              filter (where jsonb_typeof(e.value) <> 'null'))[1]
                 end as valor
            from public.retorno_mensagens rm
            cross join lateral jsonb_each(rm.sinais) e
           where rm.abertura_id = v_ab.id
             and rm.gravada_em <= v_agora
             and coalesce(rm.pede_motivo, '') <> all (c_fora_da_conversa)
           group by e.key) x;
  v_risco := coalesce((v_sinais ->> 'risco')::boolean, false);

  select l.name into v_lead_nome from public.whatsapp_leads l where l.id = v_ab.lead_id;

  -- ── As regras de 'nada', na ordem: a 1ª que casa decide ──
  -- O opt-out gravado da chave: o do gatilho da F0b no PARAR exato (ou outro anterior), só o criado até agora.
  v_opt_out := exists (select 1 from public.whatsapp_blocked_numbers b
                        where b.tipo = 'opt_out'
                          and b.created_at <= v_agora
                          and public._agenda_chave_telefone(b.phone_normalized) = v_ab.chave);
  v_canal := public.canal_bloqueado(v_ab.phone_normalized);
  if v_canal = 'cliente_final' then
    v_motivo := 'cliente_final';
  elsif coalesce((v_ult.sinais ->> 'parar')::boolean, false) and v_opt_out then
    -- 2. O PARAR que disparou, com o opt-out gravado. Depois dele, a mensagem nova cai na regra 4 (opt_out:
    --    pediu para parar e voltou a escrever, vai a "Para conferir").
    v_motivo := 'parar';
  elsif v_tem_parar_largo or (v_tem_parar and not v_opt_out) then
    -- 3. O PARAR por extenso em qualquer mensagem do caso (não há opt-out para segurar a mensagem seguinte) e o
    --    PARAR exato sem opt-out gravado: a transcrição do áudio só faz UPDATE do body, que o gatilho AFTER
    --    INSERT da F0b não vê, ou o gatilho falhou. Sem o opt-out a confirmação mentiria e o pedido se perderia:
    --    vai a "Para conferir", sem resposta, e o dono decide.
    v_motivo := 'parar_largo';
  elsif v_canal = 'opt_out' or v_opt_out then
    v_motivo := 'opt_out';
  elsif v_canal is not null then
    -- A lista de spam (ou um opt-out gravado só depois de agora, no replay): na dúvida, nada.
    v_motivo := 'bloqueado';
  elsif exists (select 1 from public.whatsapp_leads l
                 where l.lead_tipo = 'pessoal'
                   and public._agenda_chave_telefone(l.phone_normalized) = v_ab.chave) then
    v_motivo := 'pessoal';
  elsif v_ab.papel = 'fornecedor' then
    v_motivo := 'fornecedor';
  elsif v_ab.papel = 'contato_conhecido' then
    v_motivo := 'contato_conhecido';
  elsif v_ab.papel = 'cliente_parceiro' then
    v_motivo := 'parceiro_f4';
  elsif v_ab.papel = 'numero_novo' and v_tem_vendedor then
    -- Cliente cadastrado nunca é vendedor (palavras.ts): a regra só vale ao número novo.
    v_motivo := 'vendedor';
  elsif v_n_pede > 0 and v_n_pede_livre = 0 then
    v_motivo := 'agenda_consumiu';
  elsif v_n_pede = 0 and v_tem_robo then
    v_motivo := 'robo';
  elsif v_n_pede = 0 then
    v_motivo := 'nao_pede_resposta';
  else
    -- 12. A promessa do dono (promessa.ts), só a criada até agora e ainda por vencer.
    select min(w.lembrar_em) into v_prometido
      from public.whatsapp_acompanhamentos w
     where w.modo = 'promessa'
       and w.status = 'ativo'
       and public._agenda_chave_telefone(w.phone_normalized) = v_ab.chave
       and w.created_at <= v_agora
       and w.lembrar_em > v_agora;
    if v_prometido is not null then
      v_motivo := 'promessa_do_dono';
    elsif v_ab.papel = 'numero_novo' then
      -- 13. O pedido de serviço nas 24 h do NÚMERO (B.2): a janela começa na hora real da 1ª recebida da chave
      --     nas 24 h antes de agora (um caso fechado por silêncio não apaga o "motorhome" dito de manhã).
      select min(public._retorno_hora_real(w)) into v_desde
        from public.whatsapp_messages w
       where public._agenda_chave_telefone(w.phone_normalized) = v_ab.chave
         and w.direction = 'inbound'
         and w.occurred_at <= v_agora
         and w.occurred_at >= v_agora - interval '24 hours'
         and public._retorno_hora_real(w) >= v_agora - interval '24 hours';
      if v_desde is not null then
        v_pd := public._retorno_pedido_de_servico(v_ab.chave, v_desde, v_agora, v_lead_nome);
      end if;
      -- O pedido achado antes não se perde quando a janela passa (o caso não regride depois do recibo).
      v_pedido := coalesce((v_pd ->> 'pedido')::boolean, false)
                  or v_ab.tipo_recibo is not distinct from 'recibo_numero_novo'
                  or exists (select 1 from public.retorno_saidas s
                              where s.abertura_id = v_ab.id and s.tipo = 'recibo_numero_novo');
      if v_pedido then
        v_tipo := 'recibo_numero_novo';
      elsif v_n_pede_saudacao = v_n_pede then
        v_tipo := 'saudacao_numero_novo';
      else
        v_motivo := 'numero_novo_sem_pedido';
      end if;
    elsif v_ab.papel = 'cliente_ambiguo' then
      v_tipo := 'recibo_ambiguo';
    else
      v_tipo := 'recibo_cliente';
    end if;
  end if;

  if v_motivo is not null then
    v_nivel := 'nada';
    v_tipo := null;
  else
    v_nivel := 'recibo';
    -- Passagem imediata (B.4: recibo + acorde).
    v_passagem := v_risco
                  or coalesce((v_sinais ->> 'reclamacao')::boolean, false)
                  or coalesce((v_sinais ->> 'quer_dono')::boolean, false)
                  or coalesce((v_sinais ->> 'lgpd')::boolean, false)
                  or v_insistencias >= 2;
    if v_vencido then
      -- Vencido desde o fim do dia (ou o prazo final; na promessa do dono, o prometido_ate dela); a mensagem nova
      -- que pede resposta vira passagem (R1-07).
      v_vencida_desde := coalesce(least(v_ab.fim_do_dia_em, coalesce(v_ab.segundo_prazo, v_ab.prometido_ate)),
                                  v_ab.recibo_em, v_ab.aberta_em);
      v_passagem := v_passagem
                    or exists (select 1 from public.retorno_mensagens rm
                                where rm.abertura_id = v_ab.id and rm.pede_resposta
                                  and rm.gravada_em > v_vencida_desde and rm.gravada_em <= v_agora);
    end if;
    if v_passagem then
      v_nivel := 'passagem';
    end if;
  end if;

  v_intencao := case
    when v_motivo in ('parar', 'parar_largo') then 'parar'
    when v_risco then 'risco'
    when coalesce((v_sinais ->> 'lgpd')::boolean, false) then 'lgpd'
    when coalesce((v_sinais ->> 'reclamacao')::boolean, false) then 'reclamacao'
    when coalesce((v_sinais ->> 'quer_dono')::boolean, false) then 'quer_dono'
    when coalesce((v_sinais ->> 'pressa')::boolean, false) or coalesce((v_sinais ->> 'urgente')::boolean, false) then 'pressa'
    when v_pedido or (v_ab.papel <> 'numero_novo' and coalesce((v_sinais ->> 'servico')::boolean, false)) then 'pedido_servico'
    when v_n_pede > 0 and v_n_pede_saudacao = v_n_pede then 'saudacao'
    else 'outro'
  end;

  update public.retorno_aberturas ab
     set nivel = v_nivel,
         motivo = v_motivo,
         tipo_recibo = v_tipo,
         sinais = v_sinais,
         intencao = v_intencao,
         insistencias = least(v_insistencias, 32767),
         passagem_em = case when v_nivel = 'passagem' then coalesce(ab.passagem_em, v_agora) else ab.passagem_em end,
         -- a promessa do dono vira o relógio; a que saiu ANTES do prazo (encerrada ou cancelada, com prometido_ate
         -- ainda por vir) num caso aberto e sem recibo sai do relógio, e o recibo assume. A que VENCEU fica: o caso
         -- está vencido (passagem, nunca recibo novo) e o vigia o marca por ela. No caso vencido também fica, para
         -- a história do que foi prometido.
         prometido_ate = case when v_motivo = 'promessa_do_dono' then v_prometido
                              when ab.prometido_fonte = 'dono' and ab.recibo_em is null and ab.estado = 'aberta'
                                   and ab.prometido_ate > v_agora then null
                              else ab.prometido_ate end,
         prometido_fonte = case when v_motivo = 'promessa_do_dono' then 'dono'
                                when ab.prometido_fonte = 'dono' and ab.recibo_em is null and ab.estado = 'aberta'
                                     and ab.prometido_ate > v_agora then null
                                else ab.prometido_fonte end,
         faixa = case when v_motivo = 'promessa_do_dono' then 'promessa_dono'
                      when ab.prometido_fonte = 'dono' and ab.recibo_em is null and ab.estado = 'aberta'
                           and ab.prometido_ate > v_agora then null
                      else ab.faixa end,
         atualizada_em = now()
   where ab.id = v_ab.id
   returning * into v_ab;

  -- ── As saídas ──
  select * into v_recibo from public.retorno_saidas s where s.dedupe_key = 'retorno:' || v_ab.id || ':recibo';
  select * into v_saudacao from public.retorno_saidas s where s.dedupe_key = 'retorno:' || v_ab.id || ':saudacao';

  if v_nivel = 'nada' then
    -- O caso que vira 'nada' cancela as agendadas (recibo, saudação, coleta, urgente, cadastro e avisos), menos
    -- a confirmação do PARAR e o acorde. A saída que o retorno_pegar está processando é pulada: ele mesmo a
    -- cancela pelo _retorno_checar_antes.
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'nivel_nada', decidida_em = v_agora, atualizada_em = now()
     where s.id in (select x.id from public.retorno_saidas x
                     where x.abertura_id = v_ab.id and x.estado = 'agendada' and x.tipo not in ('parar', 'acorde')
                     for update skip locked);

    -- A confirmação do PARAR (T27/T28): uma, só a quem pode ouvir resposta, nunca a vendedor nem a robô (C12).
    -- O motivo 'parar' já exige o opt-out gravado (regra 2): sem ele, a confirmação nunca nasce.
    if v_motivo = 'parar' and v_ab.papel in ('cliente', 'cliente_ambiguo', 'numero_novo')
       and not v_tem_vendedor and not v_tem_robo then
      insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                         estado, enviar_em, dados, dedupe_key)
      values (v_ab.id, 'parar', 'retorno_recibo', 'resposta_imediata', v_ab.chave, v_ab.phone_normalized,
              v_ab.client_id, v_ab.modo, 'agendada', v_ult.gravada_em + make_interval(mins => v_cfg.carencia_min),
              jsonb_build_object('mensagem', v_ult.whatsapp_message_id), 'retorno:' || v_ab.id || ':parar')
      on conflict (dedupe_key) do nothing;
    end if;
  else
    -- A carência adaptativa (B.8): o dono ativo (saída humana a qualquer número nos últimos 15 min, só as
    -- gravadas até agora) ganha mais tempo para responder antes do recibo.
    v_dono_ativo := exists (select 1 from public.whatsapp_messages o
                             where o.direction = 'outbound'
                               and o.occurred_at <= v_agora
                               and o.occurred_at > v_agora - make_interval(mins => v_cfg.dono_ativo_janela_min)
                               and coalesce(o.saida_humana, public._saida_e_humana(o.direction, o.raw_payload, o.sent_by)));
    v_carencia := make_interval(mins => case when v_dono_ativo then v_cfg.carencia_dono_ativo_min
                                             else v_cfg.carencia_min end);

    if v_tipo = any (c_recibos) then
      -- O pedido apareceu depois da saudação: a saudação ainda agendada é substituída pelo recibo.
      if v_saudacao.estado = 'agendada' then
        update public.retorno_saidas s
           set estado = 'cancelada', motivo = 'substituida', decidida_em = v_agora, atualizada_em = now()
         where s.id in (select x.id from public.retorno_saidas x
                         where x.id = v_saudacao.id and x.estado = 'agendada'
                         for update skip locked);
      end if;
      -- Caso vencido não ganha recibo novo (só o acorde da passagem), nem o da promessa do dono que passou.
      if not v_vencido then
        v_enviar := v_ab.ultima_gravada_em + v_carencia;
        if v_ab.papel = 'numero_novo' and v_tem_audio then
          -- Número novo que só mandou áudio espera a transcrição; o cliente identificado não (R1-29).
          v_enviar := v_ab.ultima_gravada_em + greatest(v_carencia, make_interval(mins => v_cfg.audio_espera_min));
        end if;
        insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                           estado, enviar_em, dados, dedupe_key)
        values (v_ab.id, v_tipo, 'retorno_recibo', 'resposta_imediata', v_ab.chave, v_ab.phone_normalized,
                v_ab.client_id, v_ab.modo, 'agendada', v_enviar,
                jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id, 'risco', v_risco,
                                   'apos_saudacao', coalesce(v_saudacao.estado = any (c_decididas), false)),
                'retorno:' || v_ab.id || ':recibo')
        on conflict (dedupe_key) do nothing;
        -- rr-f1-11 (20/11/2026): o número novo que pede serviço recebe, 1 minuto depois do recibo, o formulário de cadastro do
        -- dono (T36, texto fixo). Uma vez por contato: a chave que já recebeu um (enviado ou incerto) não recebe outro. Ocupa a
        -- vaga da coleta (a mesma dedupe_key): com ele, o "Como posso chamar você?" não nasce. O retorno_pegar espera o recibo.
        -- Só com a resposta a número novo ligada (o interruptor de sempre): desligada, a triagem é a de hoje, byte a byte.
        if v_tipo = 'recibo_numero_novo' and public._retorno_numero_novo_ligado()
           and not exists (select 1 from public.retorno_saidas o
                            where o.chave = v_ab.chave and o.tipo = 'coleta_numero_novo' and o.variante = 'formulario'
                              and o.estado in ('enviada', 'incerta')) then
          insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo,
                                             estado, enviar_em, dados, dedupe_key)
          values (v_ab.id, 'coleta_numero_novo', 'formulario', 'retorno_coleta', 'resposta_imediata', v_ab.chave,
                  v_ab.phone_normalized, v_ab.client_id, v_ab.modo, 'agendada', v_enviar + interval '1 minute',
                  jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id), 'retorno:' || v_ab.id || ':coleta')
          on conflict (dedupe_key) do nothing;
          -- A rajada empurra o recibo; o formulário vai junto, sempre 1 minuto depois.
          update public.retorno_saidas s
             set enviar_em = v_enviar + interval '1 minute', atualizada_em = now()
           where s.id in (select x.id from public.retorno_saidas x
                           where x.dedupe_key = 'retorno:' || v_ab.id || ':coleta'
                             and x.variante = 'formulario' and x.estado = 'agendada'
                             and x.enviar_em < v_enviar + interval '1 minute'
                           for update skip locked);
        end if;
        -- A rajada: mensagem nova com o recibo ainda agendado empurra o envio (nunca adianta); o risco que
        -- apareceu depois (inclusive pela transcrição) entra nos dados (o P6 põe a linha L01).
        update public.retorno_saidas s
           set enviar_em = case when s.dados ->> 'ultima_msg_id' is distinct from v_ab.ultima_msg_id::text
                                then greatest(s.enviar_em, v_enviar) else s.enviar_em end,
               dados = s.dados || jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id, 'risco', v_risco),
               atualizada_em = now()
         where s.id in (select x.id from public.retorno_saidas x
                         where x.dedupe_key = 'retorno:' || v_ab.id || ':recibo'
                           and x.estado = 'agendada'
                           and (x.dados ->> 'ultima_msg_id' is distinct from v_ab.ultima_msg_id::text
                                or x.dados -> 'risco' is distinct from to_jsonb(v_risco))
                         for update skip locked);
      end if;
    elsif v_tipo = 'saudacao_numero_novo' and not v_vencido then
      v_enviar := v_ab.ultima_gravada_em + make_interval(mins => v_cfg.saudacao_espera_min);
      insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                         estado, enviar_em, dados, dedupe_key)
      values (v_ab.id, 'saudacao_numero_novo', 'retorno_recibo', 'resposta_imediata', v_ab.chave,
              v_ab.phone_normalized, v_ab.client_id, v_ab.modo, 'agendada', v_enviar,
              jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id), 'retorno:' || v_ab.id || ':saudacao')
      on conflict (dedupe_key) do nothing;
      update public.retorno_saidas s
         set enviar_em = greatest(s.enviar_em, v_enviar),
             dados = s.dados || jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id),
             atualizada_em = now()
       where s.id in (select x.id from public.retorno_saidas x
                       where x.dedupe_key = 'retorno:' || v_ab.id || ':saudacao'
                         and x.estado = 'agendada'
                         and x.dados ->> 'ultima_msg_id' is distinct from v_ab.ultima_msg_id::text
                       for update skip locked);
    end if;

    -- URGENTE depois do recibo decidido (sombra, enviada ou incerta): "Anotado como urgente" (T25/T26); o P6
    -- grava o topo_dia ao compor.
    if v_recibo.estado = any (c_decididas) and v_recibo.decidida_em <= v_agora then
      select rm.whatsapp_message_id as msg, rm.gravada_em into r
        from public.retorno_mensagens rm
       where rm.abertura_id = v_ab.id
         and coalesce((rm.sinais ->> 'urgente')::boolean, false)
         and rm.recebida_em > v_recibo.decidida_em
         and rm.gravada_em <= v_agora
       order by rm.recebida_em, rm.whatsapp_message_id
       limit 1;
      if found then
        insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized,
                                           client_id, modo, estado, enviar_em, dados, dedupe_key)
        values (v_ab.id, 'urgente',
                case when v_ab.papel = 'cliente' and public._retorno_nome(v_ab.client_id) is not null
                     then 'sem_acorde' else 'sem_acorde_sem_nome' end,
                'retorno_recibo', 'resposta_imediata', v_ab.chave, v_ab.phone_normalized, v_ab.client_id, v_ab.modo,
                'agendada', r.gravada_em + make_interval(mins => v_cfg.carencia_min),
                jsonb_build_object('mensagem', r.msg), 'retorno:' || v_ab.id || ':urgente')
        on conflict (dedupe_key) do nothing;
      end if;
    end if;

    -- A 2ª mensagem da coleta (C1, R1-23): número novo, recibo com pergunta já decidido, menos de coleta_max
    -- mensagens, e uma resposta que PEDE resposta depois dele ("ok", figurinha e robô não são resposta).
    if v_ab.papel = 'numero_novo' and v_recibo.estado = any (c_decididas) and v_recibo.decidida_em <= v_agora
       and coalesce(v_recibo.variante, '') like 'pergunta%' and v_ab.coleta_n < v_cfg.coleta_max then
      select rm.whatsapp_message_id as msg, rm.gravada_em into r
        from public.retorno_mensagens rm
       where rm.abertura_id = v_ab.id
         and rm.pede_resposta
         and rm.recebida_em > v_recibo.decidida_em
         and rm.gravada_em > v_recibo.decidida_em
         and rm.gravada_em <= v_agora
       order by rm.recebida_em, rm.whatsapp_message_id
       limit 1;
      if found then
        insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized,
                                           client_id, modo, estado, enviar_em, dados, dedupe_key)
        values (v_ab.id, 'coleta_numero_novo', 'nome', 'retorno_coleta', 'resposta_imediata', v_ab.chave,
                v_ab.phone_normalized, v_ab.client_id, v_ab.modo, 'agendada',
                r.gravada_em + make_interval(mins => v_cfg.carencia_min),
                jsonb_build_object('mensagem', r.msg), 'retorno:' || v_ab.id || ':coleta')
        on conflict (dedupe_key) do nothing;
      end if;
    end if;

    -- O nome dito: só depois da coleta ENVIADA (a pessoa ouviu "Como posso te chamar?"). Na sombra a coleta
    -- nunca é enviada: o nome fica nulo e o cadastro nunca é tentado (R-7).
    v_nome := v_ab.coleta ->> 'nome';
    if v_ab.papel = 'numero_novo' and v_nome is null then
      select * into v_coleta_saida from public.retorno_saidas s where s.dedupe_key = 'retorno:' || v_ab.id || ':coleta';
      if v_coleta_saida.estado = 'enviada' and v_coleta_saida.enviada_em <= v_agora then
        -- rr-f1-11: o formulário respondido ("Nome: ...") vale antes da regra do nome dito.
        select coalesce(public._retorno_formulario_lido(w.body) ->> 'nome', public._retorno_nome_dito(w.body)),
               public._retorno_formulario_lido(w.body)
          into v_nome, v_form
          from public.retorno_mensagens rm
          join public.whatsapp_messages w on w.id = rm.whatsapp_message_id
         where rm.abertura_id = v_ab.id
           and rm.pede_resposta
           and rm.recebida_em > v_coleta_saida.enviada_em
           and rm.gravada_em <= v_agora
           and w.occurred_at <= v_agora
           and coalesce(public._retorno_formulario_lido(w.body) ->> 'nome', public._retorno_nome_dito(w.body)) is not null
         order by rm.recebida_em, rm.whatsapp_message_id
         limit 1;
        if v_nome is not null then
          insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, client_id, modo, estado,
                                             enviar_em, dados, dedupe_key)
          values (v_ab.id, 'cadastro_provisorio', v_ab.chave, v_ab.phone_normalized, v_ab.client_id, v_ab.modo,
                  'agendada', v_agora, '{}'::jsonb, 'retorno:' || v_ab.id || ':cadastro')
          on conflict (dedupe_key) do nothing;
        end if;
      end if;
    end if;

    -- A coleta (C1): o que o número novo escreveu, literal, no formato de dados_site (lead-do-site.ts), em
    -- retorno_aberturas.coleta e em whatsapp_leads.coleta. Sem inferência: o tipo é o rótulo da palavra dita
    -- (os modelos não viram tipo); o modelo é "modelo ano" literal; o serviço, as palavras achadas.
    if v_ab.papel = 'numero_novo' and v_tipo = 'recibo_numero_novo' and coalesce((v_pd ->> 'pedido')::boolean, false) then
      select string_agg(p.palavra, ', ' order by p.primeira) into v_servicos
        from (select x.palavra, min(x.ordem) as primeira
                from (select mt.m[1] as palavra, w.ord * 1000 + mt.n as ordem
                        from jsonb_array_elements_text(v_pd -> 'msgs') with ordinality as w(id, ord)
                        join public.whatsapp_messages wm on wm.id = w.id::uuid
                        cross join lateral regexp_matches(public._retorno_busca(wm.body), c_re_servico, 'g')
                             with ordinality as mt(m, n)) x
               group by x.palavra) p;
      v_tipo_bem := case v_pd ->> 'bem_palavra'
        when 'lancha' then 'Lancha' when 'veleiro' then 'Veleiro' when 'catamara' then 'Catamarã'
        when 'jet ski' then 'Moto aquática' when 'moto aquatica' then 'Moto aquática'
        when 'barco' then 'Barco' when 'embarcacao' then 'Embarcação' when 'escuna' then 'Escuna'
        when 'traineira' then 'Traineira' when 'bote' then 'Bote'
        when 'motorhome' then 'Motorhome' when 'trailer' then 'Trailer' when 'camper' then 'Camper'
        when 'van' then 'Van' when 'onibus' then 'Ônibus' when 'caminhao' then 'Caminhão' when 'picape' then 'Picape'
        when 'automovel' then 'Automóvel' when 'carro' then 'Automóvel' when 'veiculo' then 'Veículo'
        else null   -- ducato, sprinter, iveco, daily, master, boxer: modelo, não tipo
      end;
      v_modelo := nullif(btrim(concat_ws(' ', v_pd ->> 'modelo', v_pd ->> 'ano')), '');
      v_coleta := jsonb_build_object('nome', v_nome, 'tipo', v_tipo_bem, 'modelo', v_modelo, 'local', null::text,
                                     'servico', v_servicos, 'detalhes', v_pd ->> 'pedido_literal', 'fonte', 'retorno',
                                     'ano', v_pd ->> 'ano', 'atualizado_em', v_agora);
    elsif v_nome is not null and v_ab.coleta ->> 'nome' is null then
      -- O nome chegou depois que a janela de 24 h do pedido passou: só o nome entra.
      v_coleta := coalesce(v_ab.coleta, jsonb_build_object('tipo', null::text, 'modelo', null::text, 'local', null::text,
                                                           'servico', null::text, 'detalhes', null::text,
                                                           'fonte', 'retorno', 'ano', null::text))
                  || jsonb_build_object('nome', v_nome, 'atualizado_em', v_agora);
    end if;
    -- rr-f1-11: os campos do formulário respondido ficam na coleta, literais (formulario), e o CPF vira o documento que o
    -- cadastro provisório usa para achar duplicado. Nas triagens seguintes, o que já foi lido fica.
    if v_coleta is not null and (v_form is not null or v_ab.coleta ? 'formulario') then
      v_coleta := v_coleta || jsonb_strip_nulls(jsonb_build_object(
        'formulario', coalesce(v_form, v_ab.coleta -> 'formulario'),
        'documento', coalesce(v_form ->> 'cpf', v_ab.coleta ->> 'documento')));
    end if;
    if v_coleta is not null then
      update public.retorno_aberturas ab
         set coleta = v_coleta, atualizada_em = now()
       where ab.id = v_ab.id
         and (ab.coleta - 'atualizado_em') is distinct from (v_coleta - 'atualizado_em');
      update public.whatsapp_leads l
         set coleta = v_coleta
       where l.id = v_ab.lead_id
         and (l.coleta - 'atualizado_em') is distinct from (v_coleta - 'atualizado_em');
    end if;

    -- A passagem: um acorde por mensagem que a causou (risco, LGPD, reclamação, "quero falar com o Gustavo",
    -- a que pede num caso vencido, ou a 2ª insistência em diante, pela conta recalculada acima: a mensagem
    -- que só chegou depois, sem ser insistência, não ganha acorde). Se a agenda já levou essa mensagem ao
    -- dono, ela já o acordou (R1-09): o acorde nasce cancelado. O acorde é decidido no SQL pelo vigia (P6).
    if v_nivel = 'passagem' then
      for r in
        select rm.whatsapp_message_id as msg, rm.agenda_ao_dono as ao_dono,
               case when coalesce((rm.sinais ->> 'risco')::boolean, false) then 'risco'
                    when coalesce((rm.sinais ->> 'lgpd')::boolean, false) then 'lgpd'
                    when coalesce((rm.sinais ->> 'reclamacao')::boolean, false) then 'reclamacao'
                    when coalesce((rm.sinais ->> 'quer_dono')::boolean, false) then 'quer_dono'
                    when v_vencido and rm.pede_resposta and rm.gravada_em > v_vencida_desde then 'vencida'
                    else 'insistencia'
               end as por
          from public.retorno_mensagens rm
         where rm.abertura_id = v_ab.id
           and rm.gravada_em <= v_agora
           and coalesce(rm.pede_motivo, '') <> all (c_fora_da_conversa)
           and (coalesce((rm.sinais ->> 'risco')::boolean, false)
                or coalesce((rm.sinais ->> 'lgpd')::boolean, false)
                or coalesce((rm.sinais ->> 'reclamacao')::boolean, false)
                or coalesce((rm.sinais ->> 'quer_dono')::boolean, false)
                or (v_vencido and rm.pede_resposta and rm.gravada_em > v_vencida_desde)
                or rm.whatsapp_message_id = any (v_insiste_acorde))
         order by rm.recebida_em, rm.whatsapp_message_id
      loop
        insert into public.retorno_saidas (abertura_id, tipo, variante, chave, phone_normalized, client_id, modo,
                                           estado, motivo, enviar_em, decidida_em, dados, dedupe_key)
        values (v_ab.id, 'acorde', 'passagem', v_ab.chave, v_ab.phone_normalized, v_ab.client_id, v_ab.modo,
                case when r.ao_dono then 'cancelada' else 'agendada' end,
                case when r.ao_dono then 'agenda_ja_acordou' end,
                v_agora, case when r.ao_dono then v_agora end,
                jsonb_build_object('mensagem', r.msg, 'por', r.por),
                'retorno:' || v_ab.id || ':acorde:' || r.msg)
        on conflict (dedupe_key) do nothing;
      end loop;
    end if;
  end if;

  select s.id into v_saida_id from public.retorno_saidas s
   where s.dedupe_key in ('retorno:' || v_ab.id || ':recibo', 'retorno:' || v_ab.id || ':saudacao')
   order by (s.dedupe_key like '%:recibo') desc limit 1;

  return jsonb_build_object('abertura_id', v_ab.id, 'papel', v_ab.papel, 'nivel', v_nivel, 'motivo', v_motivo,
                            'tipo_recibo', v_tipo, 'estado', v_ab.estado, 'modo', v_ab.modo, 'saida_id', v_saida_id);
end;
$$;

create or replace function public.retorno_pegar(p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  c_contam constant text[] := array['sombra', 'preparada', 'enviando', 'enviada', 'incerta'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_cfg public.retorno_config;
  v_volta integer;
  v_s public.retorno_saidas;
  v_ab public.retorno_aberturas;
  v_ch jsonb;
  v_pz jsonb;
  v_pd jsonb;
  v_desde timestamptz;
  v_dados jsonb;
  v_campos jsonb;
  v_nome text;
  v_var text;
  v_texto text;
  v_modo jsonb;
  v_ligado boolean;
  v_canal jsonb;
  v_pretendido boolean;
  v_ouviu boolean;
  v_volta_atraso boolean;
  v_topo date;
  v_do_bem text;
  v_apos_saudacao boolean;
  v_ctx jsonb;
  v_m jsonb;           -- F2
  v_f2 boolean;        -- F2
  v_alt text;          -- F2
  v_acorde boolean;    -- F2 (P14)
  v_rec public.retorno_saidas;   -- rr-f1-11: o recibo do caso, para o formulário
begin
  v_cfg := public._retorno_cfg();
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return null;
  end if;

  for v_volta in 1 .. 10 loop
    -- 1. Uma saída devida, fora de reserva, que só a edge decide. Duas execuções nunca pegam a mesma.
    select * into v_s
      from public.retorno_saidas s
     where s.estado = 'agendada'
       and s.enviar_em <= v_agora
       and (s.processando_ate is null or s.processando_ate < v_agora)
       and s.tipo not in ('acorde', 'cadastro_provisorio', 'fila')
       and s.emissor not in ('parceiro', 'orcamento')   -- F4 (P5) e F5 (P5): as saídas do parceiro e do orçamento têm o pegar delas
     order by s.enviar_em, s.id
     limit 1
     for update skip locked;
    if not found then
      return null;
    end if;

    begin
      -- 2. Conferir de novo, agora.
      v_ch := public._retorno_checar_antes(v_s.id, v_agora);
      if v_ch ->> 'acao' = 'cancelar' then
        update public.retorno_saidas s
           set estado = 'cancelada', motivo = v_ch ->> 'motivo', decidida_em = v_agora, processando_ate = null,
               atualizada_em = now()
         where s.id = v_s.id and s.estado = 'agendada';
        if v_ch ->> 'motivo' = 'respondida_pelo_dono' then
          update public.retorno_aberturas a
             set respondida_em = coalesce(a.respondida_em, (v_ch -> 'resposta' ->> 'respondida_em')::timestamptz),
                 atualizada_em = now()
           where a.id = v_s.abertura_id;
        end if;
        continue;
      elsif v_ch ->> 'acao' = 'adiar' then
        update public.retorno_saidas s
           set enviar_em = (v_ch ->> 'enviar_em')::timestamptz,
               dados = s.dados || jsonb_build_object('adiada', jsonb_build_object('motivo', v_ch ->> 'motivo', 'em', v_agora)),
               atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;

      -- A triagem pode ter mexido na saída (o risco que apareceu) e no caso: lê de novo.
      select * into v_s from public.retorno_saidas s where s.id = v_s.id;
      select * into v_ab from public.retorno_aberturas a where a.id = v_s.abertura_id;

      -- rr-f1-11 (20/11/2026): o formulário sai depois do recibo do caso. Recibo por decidir: espera 1 minuto. Recibo que não
      -- saiu (cancelado ou recusado) leva o formulário junto, com o mesmo motivo. Chave que já recebeu um formulário: não
      -- recebe outro. Recibo em sombra: segue, e o modo efetivo o põe em sombra também (regra 8).
      if v_s.tipo = 'coleta_numero_novo' and v_s.variante = 'formulario' then
        v_rec := null;
        select r.* into v_rec from public.retorno_saidas r
         where r.abertura_id = v_s.abertura_id and r.tipo = 'recibo_numero_novo'
         order by r.criada_em, r.id
         limit 1;
        if v_rec.id is null or v_rec.estado in ('cancelada', 'recusada') then
          update public.retorno_saidas s
             set estado = 'cancelada', motivo = coalesce(v_rec.motivo, 'caso_fechado'), decidida_em = v_agora, processando_ate = null,
                 atualizada_em = now()
           where s.id = v_s.id and s.estado = 'agendada';
          continue;
        elsif v_rec.estado not in ('sombra', 'enviada', 'incerta') then
          update public.retorno_saidas s
             set enviar_em = greatest(v_agora, coalesce(v_rec.enviar_em, v_agora)) + interval '1 minute', atualizada_em = now()
           where s.id = v_s.id;
          continue;
        elsif exists (select 1 from public.retorno_saidas o
                       where o.chave = v_s.chave and o.id <> v_s.id and o.tipo = 'coleta_numero_novo'
                         and o.variante = 'formulario' and o.estado in ('enviada', 'incerta')) then
          update public.retorno_saidas s
             set estado = 'cancelada', motivo = 'duplicado_pergunta', decidida_em = v_agora, processando_ate = null,
                 atualizada_em = now()
           where s.id = v_s.id and s.estado = 'agendada';
          continue;
        end if;
      end if;

      -- 3. Compor.
      v_dados := v_s.dados;
      v_nome := case when v_ab.papel = 'cliente' then public._retorno_nome(v_ab.client_id) end;
      v_pretendido := v_cfg.modo = 'ligado' and v_s.tipo = any (v_cfg.tipos_ligados);
      v_pz := null;
      v_campos := '{}'::jsonb;
      v_topo := null;
      v_m := null;       -- F2
      v_f2 := false;     -- F2
      v_acorde := false; -- F2 (P14)

      if v_s.tipo = any (c_recibos) or v_s.tipo = 'saudacao_numero_novo' then
        -- O prazo é do banco, gravado na 1ª composição (a mensagem da noite guarda a promessa da faixa noite).
        -- O guardado que já venceu é calculado de novo: nunca promete hora passada.
        if jsonb_typeof(v_dados -> 'prazo') = 'object' then
          v_pz := v_dados -> 'prazo';
          if (v_pz ->> 'prometido_ate')::timestamptz <= v_agora then
            v_pz := null;
          end if;
        end if;
        if v_pz is null then
          -- F2 (P14): a pressa, com vaga de acorde, sai junto com o recibo e promete o fechamento de hoje. Sem vaga, a faixa normal.
          if coalesce((v_ab.sinais ->> 'pressa')::boolean, false)
             and v_s.tipo <> 'saudacao_numero_novo'
             and v_cfg.modo = 'ligado' and 'acorde' = any (v_cfg.tipos_ligados)
             and (v_agora at time zone c_fuso)::time >= time '08:00' and (v_agora at time zone c_fuso)::time < time '20:00' then
            v_acorde := public._retorno_acordar_agora(v_ab.id, 'pressa', v_agora);
          end if;
          v_pz := public._retorno_prazo(greatest(v_ab.aberta_em, v_agora), v_ab.chave,
                                        coalesce((v_ab.sinais ->> 'pressa')::boolean, false), v_acorde);
        end if;
        v_dados := v_dados || jsonb_build_object('prazo', v_pz);
        -- Fora da janela K3: o recibo espera a manhã (com o prazo guardado).
        if (v_pz ->> 'recibo_em')::timestamptz > v_agora then
          update public.retorno_saidas s
             set enviar_em = (v_pz ->> 'recibo_em')::timestamptz, dados = v_dados, atualizada_em = now()
           where s.id = v_s.id;
          continue;
        end if;
        -- O recibo sai agora: "hoje", "amanhã" e o outro dia são vistos de HOJE, não do dia em que o prazo foi
        -- guardado (o composto às 21:59, "amanhã até as 10h", que o canal levou à manhã seguinte diz "hoje até
        -- as 10h"). A promessa (dia, hora, prometido_ate) não muda. No prazo recém-calculado nada muda: ref já
        -- é hoje.
        v_pz := v_pz || jsonb_build_object('ref', v_hoje,
                                           'quando', public._retorno_quando((v_pz ->> 'dia')::date, v_hoje),
                                           'outro_dia', (v_pz ->> 'dia')::date > v_hoje);
        v_dados := v_dados || jsonb_build_object('prazo', v_pz);
        v_volta_atraso := v_ab.atraso_gravacao >= v_cfg.volta_min and v_ab.atraso_gravacao <= v_cfg.volta_max;
        if v_s.tipo = 'saudacao_numero_novo' then
          -- a saudação (T19) não promete hora: só o cumprimento entra nos dados (e no contexto do validador)
          v_campos := jsonb_build_object('cumprimento', public._retorno_cumprimento(v_agora), 'volta', v_volta_atraso);
        else
          v_campos := jsonb_build_object('cumprimento', public._retorno_cumprimento(v_agora),
                                         'quando', v_pz ->> 'quando', 'hora', v_pz ->> 'hora',
                                         'volta', v_volta_atraso,
                                         'risco', coalesce((v_dados ->> 'risco')::boolean, false));
        end if;
      end if;

      if v_s.tipo = 'recibo_cliente' then
        if v_pz ->> 'fonte' = 'fora_ate' then
          v_var := 'fora_ate';
        elsif v_pz ->> 'faixa' = 'noite' then
          v_var := case when v_pz ->> 'quando' = 'hoje' then 'manha' else 'manha_outro_dia' end;
          -- {de_quando}: a 1ª mensagem entre 00:00 e 06:59 do mesmo dia do recibo é "desta madrugada"
          v_campos := v_campos || jsonb_build_object('de_quando',
            case when (v_ab.aberta_em at time zone c_fuso)::date = v_hoje
                      and (v_ab.aberta_em at time zone c_fuso)::time < time '07:00'
                 then 'desta madrugada' else 'de ontem à noite' end);
        elsif v_volta_atraso then
          -- a queda avisada pelo vigia da conexão entre 30 min antes da mensagem e a gravação dela (R1-03)
          v_var := case when exists (select 1 from public.app_notifications n
                                      where n.type = 'whatsapp_caiu'
                                        and n.created_at >= v_ab.aberta_em - interval '30 minutes'
                                        and n.created_at <= v_ab.gravada_em
                                        and n.created_at <= v_agora)
                        then 'volta_queda' else 'volta' end;
          v_campos := v_campos || jsonb_build_object(
            'dia_msg', public._agenda_cliente_dia((v_ab.aberta_em at time zone c_fuso)::date),
            'hora_msg', to_char(v_ab.aberta_em at time zone c_fuso, 'HH24:MI'));
        elsif coalesce((v_pz ->> 'outro_dia')::boolean, false) then
          v_var := 'outro_dia';
        else
          v_var := 'padrao';
        end if;
        if v_nome is null then
          v_var := case v_var when 'outro_dia' then 'outro_dia_sem_nome'
                              when 'manha' then 'manha_sem_nome'
                              when 'manha_outro_dia' then 'manha_sem_nome'
                              when 'fora_ate' then 'fora_ate_sem_nome'
                              else 'sem_nome' end;
        elsif v_var in ('padrao', 'outro_dia', 'manha', 'manha_outro_dia', 'fora_ate', 'volta', 'volta_queda') then
          -- VOZ-1 e VOZ-6: a Claudia se apresenta só se ninguém (retorno ou agenda) falou com este cliente.
          -- Em sombra, a sombra do retorno também conta, para a simulação sair como sairia ligada.
          v_ouviu := public._cliente_ja_apresentada(v_ab.client_id, v_s.chave, v_hoje)
                     or (not v_pretendido
                         and exists (select 1 from public.retorno_saidas o
                                      where o.chave = v_s.chave
                                        and o.id <> v_s.id
                                        and o.emissor = 'retorno'
                                        and o.tipo not in ('acorde', 'cadastro_provisorio', 'fila')
                                        and o.decidida_em > v_agora - v_cfg.apresentacao_intervalo
                                        and o.decidida_em <= v_agora
                                        and o.estado = 'sombra'));
          if not v_ouviu then
            v_var := v_var || '_apresentacao';
          end if;
        end if;

      elsif v_s.tipo = 'recibo_ambiguo' then
        v_var := 'padrao';

      elsif v_s.tipo = 'recibo_numero_novo' then
        v_apos_saudacao := coalesce((v_dados ->> 'apos_saudacao')::boolean, false)
                           or exists (select 1 from public.retorno_saidas o
                                       where o.abertura_id = v_s.abertura_id
                                         and o.tipo = 'saudacao_numero_novo'
                                         and o.estado in ('sombra', 'enviada', 'incerta')
                                         and o.decidida_em <= v_agora);
        -- rr-f1-11: com o formulário a seguir, o recibo não pergunta nada (o formulário já pede tudo; no máximo 2 mensagens).
        if v_apos_saudacao
           or exists (select 1 from public.retorno_saidas o
                       where o.abertura_id = v_s.abertura_id and o.tipo = 'coleta_numero_novo' and o.variante = 'formulario') then
          v_var := 'sem_pergunta';     -- no máximo 2 mensagens automáticas no 1º contato (R1-23)
        else
          -- O pedido das 24 h do número (a mesma janela da triagem): a necessidade dita e o bem.
          select min(public._retorno_hora_real(w)) into v_desde
            from public.whatsapp_messages w
           where public._agenda_chave_telefone(w.phone_normalized) = v_s.chave
             and w.direction = 'inbound'
             and w.occurred_at <= v_agora
             and w.occurred_at >= v_agora - interval '24 hours'
             and public._retorno_hora_real(w) >= v_agora - interval '24 hours';
          v_pd := case when v_desde is not null
                       then public._retorno_pedido_de_servico(v_s.chave, v_desde, v_agora, null) end;
          v_do_bem := public._retorno_do_bem(coalesce(v_pd ->> 'bem_palavra', v_ab.sinais ->> 'bem_palavra'));
          if coalesce((v_pd ->> 'servico_generico')::boolean, false) then
            v_var := 'pergunta_necessidade';
          elsif coalesce(v_pd ->> 'ano', v_ab.sinais ->> 'ano') is null and v_do_bem is not null then
            v_var := 'pergunta_modelo';
            v_campos := v_campos || jsonb_build_object('do_bem', v_do_bem);
          else
            v_var := 'sem_pergunta';   -- sem a palavra do bem não há como perguntar o modelo
          end if;
        end if;

      elsif v_s.tipo = 'saudacao_numero_novo' then
        v_var := 'padrao';

      elsif v_s.tipo = 'coleta_numero_novo' then
        v_var := case when v_s.variante = 'formulario' then 'formulario' else 'nome' end;   -- rr-f1-11

      elsif v_s.tipo = 'adiamento' then
        v_var := case when v_nome is null then 'sem_nome' else 'com_nome' end;
        v_campos := jsonb_build_object('hora', v_dados ->> 'hora');

      elsif v_s.tipo in ('fim_do_dia', 'urgente') then
        -- A marca de topo vem antes do texto: é o que torna verdadeiro "o primeiro da lista dele … cedo".
        v_topo := public.agenda_somar_du(v_hoje + 1, 0);
        update public.retorno_aberturas a
           set topo_dia = case when a.topo_dia is null or a.topo_dia < v_hoje then v_topo
                               else least(a.topo_dia, v_topo) end,
               atualizada_em = now()
         where a.id = v_s.abertura_id
         returning * into v_ab;
        v_campos := jsonb_build_object('quando_lista', public._retorno_quando(v_topo, v_hoje));
        if v_s.tipo = 'fim_do_dia' then
          v_var := case when v_nome is null then 'sem_nome' else 'com_nome' end;
        else
          v_var := case when v_nome is null then 'sem_acorde_sem_nome' else 'sem_acorde' end;
          -- F2 (P14): o banco sabe qual das duas é verdade. "Avisei" só com o aviso de fato registrado.
          if v_cfg.modo = 'ligado' and 'acorde' = any (v_cfg.tipos_ligados)
             and public._retorno_acordar_agora(v_ab.id, 'urgente', v_agora) then
            v_var := case when v_nome is null then 'acorde_sem_nome' else 'acorde' end;
          end if;
        end if;

      elsif v_s.tipo = 'parar' then
        v_var := case when v_nome is null then 'sem_nome' else 'com_nome' end;

      -- F2: modelo com fato. O aprovado sai como o dono viu, sem recompor (a trava por hash). O sozinho confere o fato de novo.
      elsif v_s.tipo like 'modelo\_%' escape '\' then
        if v_dados ? 'texto_aprovado' then
          v_var := 'aprovado';
        else
          v_m := public._retorno_modelo_do_caso(v_ab.id, v_agora);
          if v_m ->> 'modelo' is distinct from v_s.tipo then
            update public.retorno_saidas s
               set estado = 'recusada', motivo = 'fato_mudou', decidida_em = v_agora, processando_ate = null, atualizada_em = now()
             where s.id = v_s.id;
            continue;
          end if;
          if exists (select 1 from public.retorno_saidas o
                      where o.abertura_id = v_s.abertura_id
                        and o.tipo in ('recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'saudacao_numero_novo')
                        and o.estado in ('enviada', 'incerta')
                        and o.decidida_em <= v_agora) then
            v_var := case when v_nome is null then 'apos_recibo_sem_nome' else 'apos_recibo' end;
          elsif v_nome is null then
            v_var := 'sem_nome';
          else
            -- VOZ-1 e VOZ-6: a Claudia se apresenta só se ninguém falou com este cliente
            v_ouviu := public._cliente_ja_apresentada(v_ab.client_id, v_s.chave, v_hoje);
            v_var := case when v_ouviu then 'padrao' else 'padrao_apresentacao' end;
          end if;
        end if;

      else
        v_var := null;   -- tipo desconhecido: o _retorno_texto recusa (22023)
      end if;

      -- F2: as variantes novas só com a chave ligada: com ela desligada, o texto ao cliente é o da F1.
      if v_cfg.variantes_ligadas then
        if v_s.tipo = 'recibo_cliente' and v_var = 'padrao' and not coalesce((v_pz ->> 'outro_dia')::boolean, false) then
          v_alt := public._retorno_variante_f2(v_ab.id, v_agora);
          if v_alt is not null then
            v_var := v_alt;
            v_f2 := true;
          end if;
        elsif v_s.tipo = 'adiamento' and public._retorno_tem_orcamento(v_ab.id, v_agora) then
          v_var := case when v_nome is null then 'orcamento_sem_nome' else 'orcamento' end;
          v_f2 := true;
        elsif v_s.tipo = 'coleta_numero_novo' and v_var = 'nome' and public._retorno_tem_orcamento(v_ab.id, v_agora) then   -- rr-f1-11: o formulário não muda
          v_var := 'nome_orcamento';
          v_f2 := true;
        end if;
      end if;

      if v_nome is not null then
        v_campos := v_campos || jsonb_build_object('nome', v_nome);
      end if;
      v_dados := v_dados || jsonb_strip_nulls(v_campos);

      begin
        -- F2: o modelo tem o texto dele; o resto, o da F1 ou a variante nova.
        if v_s.tipo like 'modelo\_%' escape '\' then
          v_texto := coalesce(v_dados ->> 'texto_aprovado', public._retorno_texto_do_modelo(v_ab.id, v_m, v_var, v_agora));
        elsif v_f2 then
          v_texto := public._retorno_texto_f2(v_s.tipo, v_var, v_dados);
        else
          v_texto := public._retorno_texto(v_s.tipo, v_var, v_dados);
        end if;
      exception when sqlstate '22023' then
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'texto', variante = left(v_var, 40), decidida_em = v_agora,
               processando_ate = null, dados = v_dados || jsonb_build_object('texto_erro', left(sqlerrm, 200)),
               atualizada_em = now()
         where s.id = v_s.id;
        perform public._retorno_log('pegar', 'retorno_pegar: ' || sqlerrm, 'error',
                                    jsonb_build_object('saida', v_s.id, 'sqlstate', '22023'));
        continue;
      end;

      -- F2: o dia da peça entra no contexto do validador.
      if v_s.tipo = 'modelo_peca_chegou' then
        v_dados := v_dados || jsonb_strip_nulls(jsonb_build_object('dia_peca', (regexp_match(v_texto, '[0-9]{2}/[0-9]{2}'))[1]));
      end if;

      -- 4. O modo efetivo (P4): o grupo do caso, o URGENTE, a passagem sem acorde e o caso em sombra.
      v_modo := public._retorno_modo_efetivo(v_s.id, v_var, v_dados -> 'prazo', v_agora);
      v_ligado := v_modo ->> 'modo' = 'ligado';
      -- F2: *segura tudo* não queima a saída: ela espera a hora do segura, e *solta tudo* a traz de volta.
      if v_modo ->> 'motivo' = 'segura_tudo' then
        update public.retorno_saidas s
           set enviar_em = v_cfg.segura_tudo_ate, dados = s.dados || jsonb_build_object('segurada', true), atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;
      if v_ligado then
        v_dados := v_dados - 'sombra_motivo';
      else
        v_dados := v_dados || jsonb_build_object('sombra_motivo', coalesce(v_modo ->> 'motivo', 'modo'));
      end if;

      -- 5. O canal (P4), simulando quando a saída vai em sombra. Ligada, trava antes a linha de configuração
      --    (até o fim da transação): a 2ª execução simultânea espera aqui e o canal dela já vê o
      --    proximo_envio_em e o teto do dia da 1ª (R1-11).
      if v_ligado then
        perform 1 from public.retorno_config c where c.id for update;
      end if;
      v_canal := public.canal_pode_enviar(v_s.phone_normalized, v_s.classe, v_s.origem, v_agora, not v_ligado, v_s.tipo);
      -- F2: o envio aprovado pelo dono conta, mas pode passar do teto do dia. Bloqueio, opt-out, pessoal e cliente final nunca passam.
      if not coalesce((v_canal ->> 'pode')::boolean, false)
         and not (v_canal ->> 'motivo' = 'teto_dia' and coalesce((v_dados ->> 'aprovada')::boolean, false)) then
        if v_canal ->> 'motivo' in ('fora_da_janela', 'espacamento')
           and (v_canal ->> 'enviar_em')::timestamptz > v_agora then
          update public.retorno_saidas s
             set enviar_em = (v_canal ->> 'enviar_em')::timestamptz,
                 dados = s.dados || jsonb_strip_nulls(jsonb_build_object('prazo', v_dados -> 'prazo')),
                 atualizada_em = now()
           where s.id = v_s.id;
          continue;
        end if;
        update public.retorno_saidas s
           set estado = 'recusada', motivo = coalesce(v_canal ->> 'motivo', 'canal'), variante = left(v_var, 40),
               texto = v_texto, dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;

      -- 6. Os tetos por número (contam sombra, preparada, enviando, enviada e incerta decididas até agora).
      if v_s.tipo = any (c_recibos) or v_s.tipo = 'saudacao_numero_novo' then
        -- recibo ou saudação de OUTRO caso nas últimas 12 h (a saudação e o recibo do mesmo caso são o par do
        -- 1º contato, J.10)
        if exists (select 1 from public.retorno_saidas o
                    where o.chave = v_s.chave
                      and o.id <> v_s.id
                      and o.emissor = 'retorno'
                      and (o.tipo = any (c_recibos) or o.tipo = 'saudacao_numero_novo')
                      and o.abertura_id is distinct from v_s.abertura_id
                      and o.estado = any (c_contam)
                      and o.decidida_em <= v_agora
                      and o.decidida_em > v_agora - v_cfg.recibo_intervalo) then
          update public.retorno_saidas s
             set estado = 'recusada', motivo = 'teto_numero', variante = left(v_var, 40), texto = v_texto,
                 dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
           where s.id = v_s.id;
          continue;
        end if;
      end if;
      if v_s.tipo = 'saudacao_numero_novo'
         and exists (select 1 from public.retorno_saidas o
                      where o.chave = v_s.chave
                        and o.id <> v_s.id
                        and o.tipo = 'saudacao_numero_novo'
                        and o.estado = any (c_contam)
                        and o.decidida_em <= v_agora
                        and o.decidida_em > v_agora - v_cfg.saudacao_intervalo) then
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'teto_saudacao', variante = left(v_var, 40), texto = v_texto,
               dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;
      if v_s.tipo = 'coleta_numero_novo'
         and (select count(*) from public.retorno_saidas o
               where o.abertura_id = v_s.abertura_id
                 and o.id <> v_s.id
                 and o.tipo in ('saudacao_numero_novo', 'recibo_numero_novo', 'coleta_numero_novo')
                 and o.estado = any (c_contam)
                 and o.decidida_em <= v_agora) >= v_cfg.coleta_max then
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'teto_coleta', variante = left(v_var, 40), texto = v_texto,
               dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;

      -- 7. A reserva.
      update public.retorno_saidas s
         set estado = case when v_ligado then 'enviando' else 'preparada' end,
             texto = v_texto, dados = v_dados, variante = left(v_var, 40), decidida_em = v_agora,
             processando_ate = v_agora + interval '2 minutes',
             modo = case when v_ligado then 'ligado' else 'sombra' end,
             atualizada_em = now()
       where s.id = v_s.id
       returning * into v_s;
      if v_ligado then
        -- o espaçamento global entre saídas automáticas, sorteado (R1-11)
        update public.retorno_config c
           set proximo_envio_em = v_agora + make_interval(secs => (c.espaco_min_s
                                    + floor(random() * (c.espaco_max_s - c.espaco_min_s + 1)))::double precision)
         where c.id;
      end if;

      -- 8. O item, com o contexto do validador montado pelo banco.
      v_ctx := public._retorno_contexto_do_validador(v_s.id, v_texto, v_dados, v_agora);
      return jsonb_build_object(
        'saida_id', v_s.id,
        'tentativa', v_s.tentativa,
        'dedupe_key', v_s.dedupe_key,
        'tipo', v_s.tipo,
        'variante', v_s.variante,
        'origem', v_s.origem,
        'classe', v_s.classe,
        'modo', v_s.modo,
        'phone', v_s.phone_normalized,
        'texto', v_s.texto,
        'validador', v_ctx);
    exception when others then
      -- Erro num item nunca trava a fila: a volta é desfeita, a saída vira recusada/erro e a próxima segue.
      update public.retorno_saidas s
         set estado = 'recusada', motivo = 'erro', decidida_em = v_agora, processando_ate = null,
             dados = s.dados || jsonb_build_object('erro', jsonb_build_object('sqlstate', sqlstate,
                                                                               'mensagem', left(sqlerrm, 200))),
             atualizada_em = now()
       where s.id = v_s.id;
      perform public._retorno_log('pegar', 'retorno_pegar: ' || sqlerrm, 'error',
                                  jsonb_build_object('saida', v_s.id, 'sqlstate', sqlstate));
    end;
  end loop;
  return null;
end;
$$;

revoke all on function public._retorno_pedido_de_servico(text, timestamptz, timestamptz, text) from public, anon, authenticated;
revoke all on function public._retorno_texto(text, text, jsonb) from public, anon, authenticated;
revoke all on function public._retorno_triar(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.retorno_pegar(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_pegar(timestamptz) to service_role;

insert into supabase_migrations.schema_migrations (version, name) values ('20270214100200','retorno_f1_formulario_numero_novo');
