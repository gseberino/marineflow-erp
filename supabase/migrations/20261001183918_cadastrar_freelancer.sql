-- Cadastro de freelancer de diária numa chamada só (pedido do dono, 01/10/2026: "o João Marcelo
-- entrou no lugar do Mickael").
--
-- Até aqui freelancer novo não tinha caminho. O assistente respondeu "precisa ser feito pela tela"
-- (não há tela), e cadastrar_favorecido cria só o favorecido: sem a diária, registrar_diaria recusa
-- o dia e a pessoa nem aparece em Financeiro › Diárias. Esta função faz, de uma vez e numa
-- transação, o que o Passo 0 das Diárias fez à mão para Roberto e Mickael (28/09/2026):
--   favorecido (ou o que já existe, pelo CPF ou pelo MESMO nome)
--   + perfil de diária vigente desde o primeiro dia de trabalho
--   + conta corrente aberta nesse dia, com saldo zero
--   + categoria padrão "Diárias de freelancers"
--   + regra por CPF (Pix ao CPF dele lança sozinho como diária), quando há CPF.
--
-- p_simular = true devolve o que FARIA, sem gravar: é o texto da confirmação do assistente — o
-- "sim" é sobre o que vai acontecer de fato, e uma recusa aparece antes do "sim", não depois.
-- Nome parecido não é a mesma pessoa (regra do dono, 26/09/2026): só CPF igual ou nome igual (sem
-- diferença de maiúscula, acento ou espaço) reaproveita um cadastro.

create or replace function public.cadastrar_freelancer(
  p_nome text,
  p_valor_diaria numeric,
  p_desde date default null,        -- primeiro dia de trabalho; nulo = hoje (Brasília)
  p_chave_pix text default null,
  p_tipo_chave text default null,   -- cpf | cnpj | email | telefone | aleatoria; nulo = deduz do formato
  p_documento text default null,    -- CPF ou CNPJ, com ou sem pontuação
  p_telefone text default null,
  p_observacao text default null,
  p_simular boolean default false,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_nome text := nullif(regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g'), '');
  v_desde date := coalesce(p_desde, public._hoje_brt());
  v_doc text := nullif(public._doc_normalizado(p_documento), '');
  v_chave text := nullif(btrim(coalesce(p_chave_pix, '')), '');
  v_tipo text := nullif(lower(btrim(coalesce(p_tipo_chave, ''))), '');
  v_fone text := nullif(public.wa_normalize_phone(p_telefone), '');
  v_obs text := nullif(btrim(coalesce(p_observacao, '')), '');
  v_fav public.payees%rowtype;   -- não "record": sem CPF, v_fav.id é lido antes de qualquer select
  v_perfil_id uuid;
  v_acao text;
  v_regra text;            -- 'criada' | 'ja_existia' | 'sem_cpf'
  v_regra_categoria text;
begin
  -- Simular não grava nada: o assistente monta a confirmação antes de saber quem vai dizer "sim".
  if v_autor is null and not coalesce(p_simular, false) then
    raise exception 'Diga quem está cadastrando o freelancer.';
  end if;
  if v_nome is null then raise exception 'Diga o nome do freelancer.'; end if;
  if p_valor_diaria is null or p_valor_diaria <= 0 then
    raise exception 'Diga o valor da diária de %.', v_nome;
  end if;
  if v_desde > public._hoje_brt() then
    raise exception 'Início no futuro (%): cadastre a partir do primeiro dia trabalhado, ou de hoje.', to_char(v_desde, 'DD/MM/YYYY');
  end if;
  if v_doc is not null and length(v_doc) not in (11, 14) then
    raise exception 'CPF/CNPJ com % dígitos: o CPF tem 11 e o CNPJ 14.', length(v_doc);
  end if;

  -- Chave Pix: o tipo dito, ou deduzido quando o formato não deixa dúvida. Onze dígitos pode ser
  -- CPF ou celular — aí só com o tipo dito (ou quando é o próprio CPF informado).
  if v_chave is null then
    v_tipo := null;
  else
    if v_tipo is null then
      v_tipo := case
        when v_chave like '%@%' then 'email'
        when v_chave ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then 'aleatoria'
        when length(regexp_replace(v_chave, '\D', '', 'g')) = 14 then 'cnpj'
        when v_doc is not null and public._doc_normalizado(v_chave) = v_doc then 'cpf'
      end;
      if v_tipo is null then
        raise exception 'A chave Pix % é CPF ou telefone? Diga o tipo.', v_chave;
      end if;
    end if;
    if v_tipo not in ('cpf', 'cnpj', 'email', 'telefone', 'aleatoria') then
      raise exception 'Tipo de chave Pix inválido: "%". Use cpf, cnpj, email, telefone ou aleatoria.', p_tipo_chave;
    end if;
    if v_tipo = 'email' then
      v_chave := lower(v_chave);
      if v_chave !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
        raise exception 'E-mail da chave Pix inválido: %.', v_chave;
      end if;
    elsif v_tipo in ('cpf', 'cnpj') then
      v_chave := public._doc_normalizado(v_chave);
      if length(v_chave) <> (case v_tipo when 'cpf' then 11 else 14 end) then
        raise exception 'A chave Pix % não tem os dígitos de um %.', p_chave_pix, upper(v_tipo);
      end if;
      -- Chave Pix CPF é o CPF: vale como documento (é o que liga a regra por CPF).
      if v_tipo = 'cpf' and v_doc is null then v_doc := v_chave; end if;
    elsif v_tipo = 'telefone' then
      v_chave := nullif(public.wa_normalize_phone(v_chave), '');
      if v_chave is null then raise exception 'Telefone da chave Pix inválido: %.', p_chave_pix; end if;
      v_chave := '+' || v_chave;
    end if;
  end if;

  -- Quem já existe: pelo CPF/CNPJ; sem achar, pelo MESMO nome.
  if v_doc is not null then
    select * into v_fav from public.payees
     where public._doc_normalizado(document) = v_doc
     order by active desc, created_at limit 1;
  end if;
  if v_fav.id is null then
    select * into v_fav from public.payees
     where lower(extensions.unaccent(regexp_replace(btrim(name), '\s+', ' ', 'g'))) = lower(extensions.unaccent(v_nome))
     order by active desc, created_at limit 1;
    if v_fav.id is not null and v_doc is not null and nullif(public._doc_normalizado(v_fav.document), '') is not null then
      raise exception 'Já existe um favorecido chamado % com outro CPF/CNPJ. Confira o documento, ou cadastre com o nome completo para diferenciar os dois.', v_fav.name;
    end if;
  end if;

  if v_fav.id is not null then
    if not v_fav.active then
      raise exception '% está desativado nos favorecidos: reative o cadastro antes de dar diária a ele.', v_fav.name;
    end if;
    if exists (select 1 from public.work_profiles
                where payee_id = v_fav.id and modo_pagamento = 'diaria'
                  and (vigencia_fim is null or vigencia_fim >= v_desde)) then
      raise exception '% já tem diária cadastrada (veja em Financeiro › Diárias).', v_fav.name;
    end if;
    v_acao := 'diaria_no_cadastro_existente';
  else
    v_acao := 'criado';
  end if;

  if v_doc is null then
    v_regra := 'sem_cpf';
  else
    select set_category into v_regra_categoria from public.finance_rules
     where match_type = 'document' and lower(match_value) = v_doc
       and direction in ('debit', 'any') and status in ('active', 'proposed')
     limit 1;
    v_regra := case when found then 'ja_existia' else 'criada' end;
  end if;

  if coalesce(p_simular, false) then
    return jsonb_build_object(
      'ok', true, 'simulacao', true, 'acao', v_acao,
      'favorecido_id', v_fav.id, 'nome', coalesce(v_fav.name, v_nome),
      'valor_diaria', round(p_valor_diaria, 2), 'desde', v_desde,
      'chave_pix', v_chave, 'tipo_chave', v_tipo, 'tem_documento', v_doc is not null,
      'regra', v_regra, 'regra_categoria', v_regra_categoria);
  end if;

  if v_acao = 'criado' then
    insert into public.payees (name, kind, document, phone, pix_key, pix_key_type, default_category,
                               notes, active, conta_corrente_desde, saldo_anterior)
    values (v_nome, 'prestador', v_doc, v_fone, v_chave, v_tipo, 'Diárias de freelancers',
            v_obs, true, v_desde, 0)
    returning * into v_fav;
  else
    -- Cadastro existente: completa o que falta; a chave Pix dita agora vale (é a que se usa para pagar).
    update public.payees set
      document = coalesce(nullif(document, ''), v_doc),
      phone = coalesce(nullif(phone, ''), v_fone),
      pix_key = coalesce(v_chave, pix_key),
      pix_key_type = case when v_chave is not null then v_tipo else pix_key_type end,
      default_category = 'Diárias de freelancers',
      conta_corrente_desde = coalesce(conta_corrente_desde, v_desde)
    where id = v_fav.id
    returning * into v_fav;
  end if;

  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria,
                                    meia_diaria_ate_horas, vigencia_inicio, observacao)
  values (v_fav.id, 'diarista', 'diaria', round(p_valor_diaria, 2), 4, v_desde,
          'Diária cadastrada em ' || to_char(public._hoje_brt(), 'DD/MM/YYYY') || '. Meia diária até 4h.'
          || coalesce(' ' || v_obs, ''))
  returning id into v_perfil_id;

  if v_regra = 'criada' then
    insert into public.finance_rules (match_type, match_value, direction, set_category, set_dre_group,
                                      autonomy, origin, status, reasoning, created_by)
    values ('document', v_doc, 'debit', 'Diárias de freelancers', 'custo_direto', 'apply', 'user', 'active',
            'Pix ao CPF de ' || split_part(v_fav.name, ' ', 1) || ' é diária de freelancer (cadastro de '
            || to_char(public._hoje_brt(), 'DD/MM/YYYY') || ').', v_autor)
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'ok', true, 'acao', v_acao,
    'favorecido_id', v_fav.id, 'perfil_id', v_perfil_id, 'nome', v_fav.name,
    'valor_diaria', round(p_valor_diaria, 2), 'desde', v_desde,
    'chave_pix', v_chave, 'tipo_chave', v_tipo, 'regra', v_regra,
    'message', v_fav.name || ' cadastrado: diária de ' || public._brl(round(p_valor_diaria, 2))
      || ' desde ' || public._dia_curto(v_desde) || '.'
      || case v_acao when 'diaria_no_cadastro_existente' then ' Usei o cadastro de favorecido que já existia.' else '' end
      || case v_regra
           when 'criada' then ' Pix para o CPF dele entram sozinhos em Diárias de freelancers.'
           when 'ja_existia' then ' Já havia regra para o CPF dele (' || coalesce(v_regra_categoria, 'sem categoria') || '); mantida.'
           else ' Sem CPF: os Pix para ele vão pedir a sua confirmação na fila do extrato.' end
  );
end;
$$;

comment on function public.cadastrar_freelancer(text, numeric, date, text, text, text, text, text, boolean, uuid) is
  'Freelancer de diária numa chamada: favorecido + diária + conta corrente + categoria + regra por CPF. p_simular=true só diz o que faria. Usada pelo assistente (tool cadastrar_freelancer).';

revoke all on function public.cadastrar_freelancer(text, numeric, date, text, text, text, text, text, boolean, uuid) from public, anon;
grant execute on function public.cadastrar_freelancer(text, numeric, date, text, text, text, text, text, boolean, uuid) to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261001183918', 'cadastrar_freelancer')
on conflict (version) do nothing;
