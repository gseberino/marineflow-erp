-- Retorno rápido ao cliente, F5 (P7): o cartão. O aceite, os dados da nota e o passo da cadência no cartão da F2. Nada liga aqui.
-- Gerada por script (scripts/gerar_f5.cjs cartao): as funções novas vêm de scripts/f5_sql/p7_cartao.sql, escritas à mão;
-- retorno_cartao_abrir, _retorno_cartao_texto, _retorno_item_conferir, _retorno_decidir_letra, retorno_decidir_dito,
-- retorno_cartao_executar, retorno_ver_caso, retorno_destino_do_item, _retorno_dito_pessoal (a da 20261112200000, com
-- "where id"), _retorno_dito_resolvido, retorno_item_enviado e _retorno_tem_orcamento são geradas do corpo vigente (o do
-- banco, achado pelo md5 do prosrc), e só os trechos marcados -- F5 são novos.
--
-- 1. _orcamento_cartao_lista (C-LISTA): os casos da F2, menos o caso que vai como item de aceite, mais os aceites e os dados
--    da nota (prioridade 3, a vaga que a F2 reservou), e depois os passos à espera do *sim*; com passo à espera e as vagas
--    tomadas, a última vaga é do passo mais antigo. O passo cujo texto não se monta (sem nome, falta de dado) vira pulado e
--    não entra. Sem aceite e sem passo, é exatamente _retorno_cartao_casos.
-- 2. Os montadores (o formato de _retorno_item_montar): o aceite (letras A a D, ou nenhuma em duvida, agenda e no aviso do
--    "Fechado" que não saiu), os dados da nota (o CPF mascarado) e o passo (o texto que vai sair).
-- 3. A conferência (o *sim <PIN>* vale sobre o que o dono leu), o executor (A e C registram no banco na mesma transação; B e D
--    vão à ferramenta com executado_em; o passo aprovado agenda a saída com o texto aprovado), os tirados com *não N*, a letra,
--    o *ver*, o *resolvido*, o *pessoal* e o ditado que saiu. Os quatro últimos e os tirados chamam
--    _orcamento_aceite_fechar_antigos (P6): os aceites mais antigos do mesmo cliente seguem a decisão.
-- 4. Geradas: os trechos -- F5 só despacham para as funções novas (cada âncora vira uma chamada curta).
--
-- Com aceite_modo fora de 'cartao' e nenhum tipo da cadência em 'cartao' ou 'sozinho', a lista é a da F2 e o cartão sai
-- idêntico ao de hoje, byte a byte (P7.2 nº 1 e 18).
--
-- Sem dado. Reverter: reaplicar retorno_cartao_abrir, _retorno_cartao_texto, _retorno_item_conferir e retorno_ver_caso de
-- 20261208100400_retorno_f3_cartao.sql; _retorno_decidir_letra, retorno_decidir_dito e retorno_cartao_executar de
-- 20261208100500_retorno_f3_decidir.sql; retorno_destino_do_item e retorno_item_enviado de 20261123100500_retorno_f2_decidir.sql;
-- _retorno_dito_pessoal de 20261112200000_retorno_update_com_where.sql; _retorno_dito_resolvido de
-- 20261123100100_retorno_f2_palavras.sql e _retorno_tem_orcamento de 20261123100300_retorno_f2_modelos.sql; depois, drop function
-- das funções _orcamento_* desta migration (a retorno_carona da P8 chama _orcamento_cartao_lista dentro de begin … exception
-- when undefined_function).

-- ── 1. Auxiliares: o assunto, o motivo do que não saiu, o rótulo e o texto do passo ─────────────────────────────────────

-- O assunto do orçamento como o dono lê no cartão ("energia solar", "baterias"): o título da família, com a 1ª letra
-- minúscula, da mesma busca de _orcamento_do_servico (texto do dono, nunca do cliente). Nenhuma família: nulo.
create or replace function public._orcamento_assunto(p_os uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select (case when x.f ->> 'titulo' is null or x.f ->> 'titulo' = 'Orçamento' then null
               else lower(left(x.f ->> 'titulo', 1)) || substr(x.f ->> 'titulo', 2) end)
    from (select public._retorno_familia_rotulo(public._retorno_familias(public._retorno_busca(
                   coalesce(so.problem_description, '') || ' ' || coalesce(l.nomes, '')))) as f
            from public.service_orders so
            left join lateral (
              select string_agg(y.nome, ' ') as nomes
                from (select coalesce(pr.name, '') as nome
                        from public.service_order_parts p
                        left join public.products pr on pr.id = p.product_id
                       where p.service_order_id = so.id
                      union all
                      select coalesce(s.name_snapshot, '')
                        from public.service_order_services s
                       where s.service_order_id = so.id) y
            ) l on true
           where so.id = p_os) x;
$$;

comment on function public._orcamento_assunto(uuid) is
  'Retorno F5 (P7.1): o assunto do orçamento no cartão do dono ("energia solar", "baterias e inversor"): o título de _retorno_familia_rotulo, com a 1ª letra minúscula, da mesma busca de _orcamento_do_servico (descrição e linhas, texto do dono). Nenhuma família, ou ordem que não existe: nulo.';

revoke all on function public._orcamento_assunto(uuid) from public, anon, authenticated;

-- Por que o "Fechado" ou o pedido de dados não saiu, como o dono lê depois de "não saiu: …" (sem nome nem número).
create or replace function public._orcamento_razao_nao_saiu(p_motivo text)
returns text
language sql
immutable
security definer
set search_path = public
as $$
  select (case p_motivo
            when 'numero_compartilhado' then 'o número é de outra pessoa com os mesmos 8 dígitos'
            when 'sem_numero' then 'não achei o número de onde o cliente escreveu'
            when 'aceite_mudou' then 'o aceite mudou ou você já escreveu ao cliente'
            when 'sem_registro' then 'a OS foi criada, mas o registro do aceite não voltou'
            when 'pessoal' then 'o número está como pessoal'
            when 'equipe' then 'o número é da equipe'
            when 'opt_out' then 'o cliente pediu para não receber mensagem automática'
            when 'bloqueado' then 'o cliente pediu para parar'
            when 'parar' then 'o cliente pediu para parar'
            when 'so_reativo' then 'o retorno estava só respondendo'
            when 'segura_tudo' then '*segura tudo* estava ligado'
            when 'teto_iniciadas' then 'o limite de mensagens do dia já tinha sido atingido'
            when 'fora_da_janela' then 'ficou fora do horário de envio'
            when 'espacamento' then 'ficou fora do horário de envio'
            when 'sem_conversa' then 'o cliente ainda não tinha escrito'
            when 'sem_nome' then 'o cadastro não tem nome'
            when 'texto' then 'o texto não se montou'
            when 'validador' then 'o texto não passou na conferência'
            when 'provedor' then 'o WhatsApp recusou'
            -- (revisão das ondas 4 a 9, achado banco-4) os cancelamentos por abertura_id da F1 e da F2 (retorno_vigia,
            -- _retorno_cartao_encerrar, o caso que vira 'nada'), que também alcançam a saída agendada do orçamento
            when 'respondida_pelo_dono' then 'você já escreveu ao cliente'
            when 'caso_fechado' then 'a conversa com o cliente foi encerrada'
            when 'nivel_nada' then 'a conversa com o cliente foi encerrada'
            when 'visita_a_combinar' then 'a visita ao cliente está para combinar'
            else 'deu erro ao mandar'
          end);
$$;

comment on function public._orcamento_razao_nao_saiu(text) is
  'Retorno F5 (P7.1): o motivo de resultado.saida_nao_saiu (o "Fechado" ou o pedido de dados que não saiu) como o dono lê no cartão, sem nome nem número; inclui os cancelamentos por abertura_id da F1 e da F2 (respondida_pelo_dono, caso_fechado, nivel_nada, visita_a_combinar). A incerta tem frase própria no item ("pode não ter saído").';

revoke all on function public._orcamento_razao_nao_saiu(text) from public, anon, authenticated;

-- O rótulo do item do orçamento. 'lista' (C-LISTA, a carona e o resumo da pendência): "Ana, aceite do ORÇ-00151",
-- "Ana, lembrete do ORÇ-00151". 'dono' (o "Vai sair" e o *resolvido*): "o lembrete do ORÇ-00151 (Ana)", "a véspera do
-- ORÇ-00151 (Ana)", "o aceite do ORÇ-00151 (Ana)", "os dados da nota do ORÇ-00151 (Ana)". O 1º nome do cadastro, nunca
-- telefone; sem pronome nem artigo antes do nome (o cadastro não tem gênero).
create or replace function public._orcamento_item_rotulo(p_tipo text, p_aceite uuid, p_passo uuid, p_forma text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_client uuid;
  v_os uuid;
  v_passo text;
  v_nome text;
  v_numero text;
  v_coisa text;
begin
  if p_passo is not null then
    select a.client_id, a.service_order_id, p.passo into v_client, v_os, v_passo
      from public.orcamento_passos p
      join public.orcamento_acompanhamentos a on a.id = p.acompanhamento_id
     where p.id = p_passo;
  elsif p_aceite is not null then
    select a.client_id, a.service_order_id into v_client, v_os from public.orcamento_aceites a where a.id = p_aceite;
  end if;
  v_nome := coalesce(public._retorno_nome(v_client), 'cliente sem nome');
  select so.service_order_number into v_numero from public.service_orders so where so.id = v_os;
  v_numero := coalesce(v_numero, 'orçamento');
  v_coisa := (case when p_tipo = 'cadencia' then (case v_passo when 'vespera' then 'véspera' when 'encerramento' then 'encerramento'
                                                               else 'lembrete' end)
                   when p_tipo = 'dados_nota' then 'dados da nota'
                   else 'aceite' end);
  if p_forma = 'lista' then
    return format('%s, %s do %s', v_nome, v_coisa, v_numero);
  end if;
  return format('%s %s do %s (%s)', (case v_coisa when 'véspera' then 'a' when 'dados da nota' then 'os' else 'o' end),
                v_coisa, v_numero, v_nome);
end;
$$;

comment on function public._orcamento_item_rotulo(text, uuid, uuid, text) is
  'Retorno F5 (P7.1): o rótulo do item do orçamento (aceite, dados_nota, cadencia). lista: "Ana, aceite do ORÇ-00151" (C-LISTA, carona, pendência); dono: "o lembrete do ORÇ-00151 (Ana)" ("Vai sair", *resolvido*). 1º nome do cadastro (_retorno_nome), nunca telefone; sem número: "orçamento".';

revoke all on function public._orcamento_item_rotulo(text, uuid, uuid, text) from public, anon, authenticated;

-- O texto que o passo mandaria agora, montado como o orcamento_pegar monta (P5.1): nome e do_servico do banco e, na véspera,
-- a validade vista de hoje. A variante 'sem_nome' (nenhum texto da F5 vai sem nome) e a variante nula (só nos dados da nota:
-- nada a pedir) são tratadas antes de _orcamento_texto; a falta de dado (22023) vira 'texto'. {texto, variante} ou {motivo}.
create or replace function public._orcamento_texto_do_passo(p_passo uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_p public.orcamento_passos;
  v_a public.orcamento_acompanhamentos;
  v_dados jsonb;
  v_var text;
  v_texto text;
begin
  select * into v_p from public.orcamento_passos p where p.id = p_passo;
  if not found then
    return jsonb_build_object('motivo', 'erro');
  end if;
  select * into v_a from public.orcamento_acompanhamentos a where a.id = v_p.acompanhamento_id;
  if not found then
    return jsonb_build_object('motivo', 'erro');
  end if;
  v_dados := jsonb_strip_nulls(jsonb_build_object('nome', public._retorno_nome(v_a.client_id),
                                                  'do_servico', public._orcamento_do_servico(v_a.service_order_id)));
  if v_p.tipo = 'orc_vespera' then
    v_dados := v_dados || jsonb_strip_nulls(jsonb_build_object('validade', public._orcamento_validade_texto(v_a.validade_ate, v_hoje)));
  end if;
  begin
    v_var := public._orcamento_variante(v_p.tipo, v_a.service_order_id, v_a.client_id, v_a.chave, v_hoje, v_dados);
    if v_var = 'sem_nome' then
      return jsonb_build_object('motivo', 'sem_nome');
    end if;
    if v_var is null then
      return jsonb_build_object('motivo', 'texto');
    end if;
    v_texto := public._orcamento_texto(v_p.tipo, v_var, v_dados);
  exception when sqlstate '22023' then
    return jsonb_build_object('motivo', 'texto', 'variante', left(v_var, 40), 'erro', left(sqlerrm, 200));
  end;
  return jsonb_build_object('texto', v_texto, 'variante', v_var);
end;
$$;

comment on function public._orcamento_texto_do_passo(uuid, timestamptz) is
  'Retorno F5 (P7.1): o texto que o passo da cadência mandaria agora ({texto, variante}), com os campos do banco como o orcamento_pegar monta (nome, do_servico e, na véspera, a validade vista de hoje). sem_nome → {motivo: sem_nome}; variante nula ou falta de dado (22023) → {motivo: texto}; passo que não existe → {motivo: erro}.';

revoke all on function public._orcamento_texto_do_passo(uuid, timestamptz) from public, anon, authenticated;

-- ── 2. A lista do cartão (C-LISTA) ──────────────────────────────────────────────────────────────────────────────────────

-- Os passos à espera do *sim*: aguarda_sim, do dia dele até o prazo (ate), acompanhamento ativo e ligado, tipo em cartao ou
-- sozinho (o sozinho sem o aviso da véspera também espera o *sim*) e a F5 fora de desligado; o que já está num item vivo de
-- um cartão vivo fica de fora (como os casos da F2). Por dia e criação.
create or replace function public._orcamento_cartao_passos(p_agora timestamptz, p_limite integer)
returns table (passo_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select p.id
    from public.orcamento_passos p
    join public.orcamento_acompanhamentos a on a.id = p.acompanhamento_id
    left join public.retorno_modelo_tipos t on t.tipo = p.tipo
   where p.estado = 'aguarda_sim'
     and a.estado = 'ativo'
     and a.modo = 'ligado'
     and coalesce(t.nivel, 'desligado') in ('cartao', 'sozinho')
     and p.dia <= (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date
     and p.ate >= (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date
     and exists (select 1 from public.retorno_config c where c.id and c.orcamento_modo is distinct from 'desligado')
     and not exists (select 1
                       from public.retorno_cartao_itens i
                       join public.retorno_cartoes k on k.id = i.cartao_id
                      where i.passo_id = p.id and i.estado = 'vivo' and k.estado = 'vivo')
   order by p.dia, a.criado_em, a.id, p.id
   limit p_limite;
$$;

comment on function public._orcamento_cartao_passos(timestamptz, integer) is
  'Retorno F5 (P7.1): os passos da cadência à espera do *sim* (aguarda_sim, dia <= hoje <= ate), com o acompanhamento ativo e ligado, o tipo em cartao ou sozinho e orcamento_modo fora de desligado; fora os que já estão num item vivo de um cartão vivo. Por dia e criação.';

revoke all on function public._orcamento_cartao_passos(timestamptz, integer) from public, anon, authenticated;

-- C-LISTA. volatile: o passo cujo texto não se monta vira pulado (sem_nome ou texto) antes de entrar.
create or replace function public._orcamento_cartao_lista(p_agora timestamptz, p_limite integer)
returns table (ordem integer, tipo text, abertura_id uuid, aceite_id uuid, passo_id uuid, prioridade smallint, rotulo text)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_l jsonb;
  v_p jsonb := '[]'::jsonb;
  v_r record;
  v_t jsonb;
  v_x jsonb;
  v_max_l integer;
  v_k integer := 0;
begin
  -- L: os casos da F2 na ordem dela (menos o caso que vai como item de aceite: nunca duas vezes) e os aceites e os dados da
  -- nota (prioridade 3, que a F2 não usa: os dois nunca se misturam dentro da mesma prioridade), pela hora da mensagem.
  with ac as (
    select a.aceite_id as id, a.tipo_item as t, a.abertura_id as ab, a.hora as h
      from public._orcamento_cartao_aceites(v_agora) a
  ), l as (
    select 'caso'::text as t, c.abertura_id as ab, null::uuid as ac, c.prioridade as pr, c.ord as o, null::timestamptz as h,
           null::text as rot
      from public._retorno_cartao_casos(v_agora, null) with ordinality as c(abertura_id, prioridade, ord)
     where not exists (select 1 from ac where ac.ab = c.abertura_id)
    union all
    select ac.t, ac.ab, ac.id, 3::smallint, null::bigint, ac.h,
           (case when ac.ab is null then public._orcamento_item_rotulo(ac.t, ac.id, null, 'lista') end)
      from ac
     where not exists (select 1
                         from public.retorno_cartao_itens i
                         join public.retorno_cartoes k on k.id = i.cartao_id
                        where i.aceite_id = ac.id and i.tipo_item = ac.t and i.estado = 'vivo' and k.estado = 'vivo')
  )
  select coalesce(jsonb_agg(jsonb_build_object('tipo', l.t, 'abertura_id', l.ab, 'aceite_id', l.ac, 'prioridade', l.pr, 'rotulo', l.rot)
                            order by l.pr, l.o, l.h, l.ac), '[]'::jsonb)
    into v_l
    from l;

  -- P: os passos à espera do *sim*. O texto passa por _orcamento_texto antes de listar: sem nome ou falta de dado, o passo
  -- vira pulado (sem_nome ou texto) e não entra.
  for v_r in select c.passo_id as id from public._orcamento_cartao_passos(v_agora, null) c loop
    v_t := public._orcamento_texto_do_passo(v_r.id, v_agora);
    if v_t ->> 'texto' is null then
      update public.orcamento_passos p
         set estado = 'pulado', motivo = (case when v_t ->> 'motivo' = 'sem_nome' then 'sem_nome' else 'texto' end)
       where p.id = v_r.id and p.estado = 'aguarda_sim';
      continue;
    end if;
    v_p := v_p || jsonb_build_array(jsonb_build_object('tipo', 'cadencia', 'passo_id', v_r.id, 'prioridade', 99,
                                                       'rotulo', public._orcamento_item_rotulo('cadencia', null, v_r.id, 'lista')));
  end loop;

  -- Com p_limite nulo, tudo (a contagem); com p_limite = n e passo à espera, a última vaga é do passo mais antigo.
  v_max_l := (case when p_limite is null then jsonb_array_length(v_l)
                   when jsonb_array_length(v_p) > 0 then greatest(p_limite - 1, 0)
                   else p_limite end);
  for v_x in select e.v from jsonb_array_elements(v_l) with ordinality as e(v, i) where e.i <= v_max_l order by e.i loop
    v_k := v_k + 1;
    ordem := v_k;
    tipo := v_x ->> 'tipo';
    abertura_id := nullif(v_x ->> 'abertura_id', '')::uuid;
    aceite_id := nullif(v_x ->> 'aceite_id', '')::uuid;
    passo_id := null;
    prioridade := (v_x ->> 'prioridade')::smallint;
    rotulo := v_x ->> 'rotulo';
    return next;
  end loop;
  for v_x in select e.v from jsonb_array_elements(v_p) with ordinality as e(v, i) order by e.i loop
    exit when p_limite is not null and v_k >= p_limite;
    v_k := v_k + 1;
    ordem := v_k;
    tipo := 'cadencia';
    abertura_id := null;
    aceite_id := null;
    passo_id := (v_x ->> 'passo_id')::uuid;
    prioridade := 99;
    rotulo := v_x ->> 'rotulo';
    return next;
  end loop;
  return;
end;
$$;

comment on function public._orcamento_cartao_lista(timestamptz, integer) is
  'Retorno F5 (P7.1, C-LISTA): a lista do cartão. L = os casos de _retorno_cartao_casos (na ordem da F2), menos o caso cujo abertura_id é o de um aceite da lista, mais _orcamento_cartao_aceites (aceite e dados_nota, prioridade 3), por prioridade, posição na F2 e hora da mensagem; P = _orcamento_cartao_passos, por dia e criação, cada passo com o texto montado (sem nome ou falta de dado: pulado/sem_nome ou pulado/texto, fora da lista). p_limite nulo: L e P, todos; p_limite = n: com P, os n−1 primeiros de L e os passos até n; sem P, os n primeiros de L. {ordem, tipo (caso, aceite, dados_nota, cadencia), abertura_id, aceite_id, passo_id, prioridade (3 no aceite, 99 no passo), rotulo (só sem caso)}. Sem aceite e sem passo, igual a _retorno_cartao_casos.';

revoke all on function public._orcamento_cartao_lista(timestamptz, integer) from public, anon, authenticated;

-- ── 3. Os montadores (C-ITEM-O: o formato de _retorno_item_montar) ─────────────────────────────────────────────────────

-- O passo da cadência: o texto que vai sair (o mesmo que o *sim <PIN>* aprova), sem letras.
create or replace function public._orcamento_item_montar_passo(p_passo uuid, p_n smallint, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_p public.orcamento_passos;
  v_a public.orcamento_acompanhamentos;
  v_numero text;
  v_assunto text;
  v_texto text;
begin
  select * into v_p from public.orcamento_passos p where p.id = p_passo;
  select * into v_a from public.orcamento_acompanhamentos a where a.id = v_p.acompanhamento_id;
  select so.service_order_number into v_numero from public.service_orders so where so.id = v_a.service_order_id;
  v_assunto := public._orcamento_assunto(v_a.service_order_id);
  v_texto := public._orcamento_texto_do_passo(p_passo, p_agora) ->> 'texto';
  return jsonb_build_object(
    'tipo_item', 'cadencia',
    'modelo_tipo', v_p.tipo,
    'service_order_id', v_a.service_order_id,
    'texto_mostrado', v_texto,
    'opcoes', '[]'::jsonb,
    'fatos', jsonb_build_object('passo', v_p.passo, 'dia', v_p.dia, 'ate', v_p.ate),
    'linhas', jsonb_build_array(
      format('%s. %s do %s · %s%s · enviado %s · sem resposta do cliente desde então · espera até %s', p_n,
             (case v_p.passo when 'vespera' then 'Véspera' when 'encerramento' then 'Encerramento' else 'Lembrete' end),
             coalesce(v_numero, 'orçamento'), coalesce(public._retorno_nome(v_a.client_id), 'cliente sem nome'),
             (case when v_assunto is not null then ' · ' || v_assunto else '' end),
             coalesce(public._dia_curto((v_a.enviado_em at time zone c_fuso)::date), '?'), public._dia_curto(v_p.ate)),
      format('   ''%s''', coalesce(v_texto, '(o texto não se montou)')),
      format('   *sim <PIN>* manda hoje às %s (ou agora; depois das %s, no próximo dia útil) · *não %s* não manda',
             public._retorno_hora(v_cfg.cadencia_hora), public._retorno_hora(v_cfg.cadencia_fim), p_n)),
    'passo_id', v_p.id,
    'rotulo', public._orcamento_item_rotulo('cadencia', null, v_p.id, 'lista'),
    'hash', md5(concat_ws('|', v_p.id, v_p.estado, v_texto)));
end;
$$;

comment on function public._orcamento_item_montar_passo(uuid, smallint, timestamptz) is
  'Retorno F5 (P7.1, C-ITEM-O): o item cadencia: tipo_item cadencia, modelo_tipo = o tipo do passo, texto_mostrado = o texto que vai sair (_orcamento_texto_do_passo), opcoes vazio, as 3 linhas ("Lembrete do ORÇ-… · Ana · assunto · enviado … · sem resposta do cliente desde então · espera até …", o texto entre aspas, "*sim <PIN>* manda hoje às 10h … · *não N* não manda"), passo_id e rotulo.';

revoke all on function public._orcamento_item_montar_passo(uuid, smallint, timestamptz) from public, anon, authenticated;

-- O aceite. Com 1 candidato (detectado): o orçamento, o valor e a validade do banco, e as letras A e B (C e D com os dados da
-- nota ligados e algo a pedir). duvida e agenda: sem letra (a dúvida é do dono). O aviso do "Fechado" (ou do pedido de dados)
-- que não saiu: sem letra, com o motivo. O valor do sinal não aparece (a conta do sinal é do TS).
create or replace function public._orcamento_item_aceite(p_abertura uuid, p_aceite uuid, p_n smallint, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_doc constant text[] := array['CPF/CNPJ', 'CPF/CNPJ incompleto'];
  c_end constant text[] := array['rua', 'bairro', 'cidade', 'UF', 'CEP', 'CEP incompleto'];
  v_hoje date := (coalesce(p_agora, now()) at time zone c_fuso)::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_a public.orcamento_aceites;
  v_w record;
  v_pend boolean;
  v_so record;
  v_ids uuid[];
  v_desc text[];
  v_cands text;
  v_k integer;
  v_val date;
  v_faltas text[];
  v_var text;
  v_empresa boolean;
  v_pede text;
  v_and text[];
  v_opcoes jsonb := '[]'::jsonb;
  v_linhas jsonb;
  v_numero text;
begin
  select * into v_a from public.orcamento_aceites a where a.id = p_aceite;
  select w.body, w.message_type, coalesce(w.hora_real, w.occurred_at) as quando into v_w
    from public.whatsapp_messages w where w.id = v_a.whatsapp_message_id;
  select rm.audio_pendente into v_pend from public.retorno_mensagens rm where rm.whatsapp_message_id = v_a.whatsapp_message_id;
  select so.service_order_number, so.grand_total, so.quote_status into v_so
    from public.service_orders so where so.id = v_a.service_order_id;
  v_numero := coalesce(v_so.service_order_number, 'orçamento');

  -- A linha da mensagem é a da F2: o trecho do cliente vai só ao WhatsApp do dono.
  v_linhas := jsonb_build_array(format('%s. %s · %s · %s', p_n, coalesce(public._retorno_nome(v_a.client_id), 'cliente sem nome'),
                                       coalesce(to_char(v_w.quando at time zone c_fuso, 'HH24:MI'), '--:--'),
                                       public._retorno_trecho(v_w.body, v_w.message_type, v_pend, 140)));

  if v_a.estado in ('com_sinal', 'sem_sinal') and v_a.resultado ? 'saida_nao_saiu' then
    -- O aviso do que não saiu (volta uma vez só; sem letra).
    v_linhas := v_linhas || jsonb_build_array(format('   %s · %s', format((case when v_a.estado = 'com_sinal'
                                                                               then '%s aprovado, aguardando o sinal'
                                                                               else '%s aprovado, sem sinal' end), v_numero),
      (case when v_a.resultado ->> 'saida_nao_saiu' = 'incerta'
            then 'o ''Fechado'' pode não ter saído: confira a conversa.'
            when v_a.resultado ->> 'saida_nao_saiu_tipo' = 'orc_dados_nota'
            then format('o pedido de dados da nota não saiu: %s; responda você.', public._orcamento_razao_nao_saiu(v_a.resultado ->> 'saida_nao_saiu'))
            else format('o ''Fechado'' não saiu: %s; responda você.', public._orcamento_razao_nao_saiu(v_a.resultado ->> 'saida_nao_saiu')) end)));
  else
    -- Os orçamentos: no detectado, o dele; em duvida e agenda, os candidatos do instante da mensagem.
    v_ids := (case when v_a.estado = 'detectado' then (case when v_a.service_order_id is not null then array[v_a.service_order_id] end)
                   else v_a.candidatos end);
    select array_agg(format('%s%s', so.service_order_number,
                            coalesce(' (' || nullif(concat_ws(', ', public._orcamento_assunto(so.id),
                                                              public._dia_curto(public._orcamento_dia_envio(so.id, v_a.chave, v_w.quando))), '')
                                     || ')', ''))
                     order by so.created_at, so.service_order_number, so.id)
      into v_desc
      from public.service_orders so where so.id = any (coalesce(v_ids, '{}'::uuid[]));
    v_k := coalesce(cardinality(v_desc), 0);
    v_cands := (case when v_k <= 1 then v_desc[1]
                     else array_to_string(v_desc[1:v_k - 1], ', ') || ' e ' || v_desc[v_k] end);

    if v_k = 0 then
      v_linhas := v_linhas || jsonb_build_array(format('   O orçamento deste aceite não existe mais. *não %s* tira da lista.', p_n));
    elsif v_a.estado = 'detectado' then
      v_val := public._orcamento_ultimo_dia(v_a.service_order_id);
      v_linhas := v_linhas || jsonb_build_array('   ' || concat_ws(' · ',
        'O cliente tem 1 orçamento enviado: ' || v_cands,
        'R$ ' || public._retorno_brl(v_so.grand_total),
        (case when v_val is null then null when v_val < v_hoje then 'venceu ' || public._dia_curto(v_val)
              else 'vale até ' || public._dia_curto(v_val) end)));
      -- C e D: com os dados da nota ligados e algo que o texto pede (a variante dos dados; nula = nada a pedir; sem_nome = o
      -- pedido não sairia).
      if coalesce(v_cfg.dados_nota_ligado, false) then
        v_faltas := coalesce(public._orcamento_faltas_para_nota(v_a.client_id), '{}'::text[]);
        v_var := public._orcamento_variante('orc_dados_nota', v_a.service_order_id, v_a.client_id, v_a.chave, v_hoje,
                                            jsonb_build_object('faltas', to_jsonb(v_faltas)));
        select c.type = 'company' into v_empresa from public.clients c where c.id = v_a.client_id;
        v_pede := (case v_var
                     when 'cpf_endereco' then 'pede CPF e endereço'
                     when 'cnpj_endereco' then 'pede CNPJ e endereço'
                     when 'documento' then (case when coalesce(v_empresa, false) then 'pede o CNPJ' else 'pede o CPF' end)
                     when 'endereco' then (case when v_faltas && c_end and not (v_faltas && array['rua', 'bairro', 'cidade', 'UF'])
                                                then 'pede o CEP' else 'pede o endereço' end)
                   end);
      end if;
      v_opcoes := jsonb_build_array(jsonb_build_object('letra', 'A', 'acao', 'aceite_com_sinal'),
                                    jsonb_build_object('letra', 'B', 'acao', 'aceite_sem_sinal'));
      if v_pede is null then
        v_linhas := v_linhas || jsonb_build_array(format(
          '   Era aprovação? *%1$s A* aprova e fica aguardando o sinal · *%1$s B* converte em OS sem sinal (tudo na conclusão) · *não %1$s* não era', p_n));
      else
        v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'C', 'acao', 'aceite_com_sinal', 'pedir_dados', true),
                                                  jsonb_build_object('letra', 'D', 'acao', 'aceite_sem_sinal', 'pedir_dados', true));
        v_linhas := v_linhas || jsonb_build_array(
          format('   Era aprovação? *%1$s A* aprova e fica aguardando o sinal · *%1$s B* converte em OS sem sinal (tudo na conclusão)', p_n),
          format('   *%1$s C* = A e %2$s · *%1$s D* = B e %2$s · *não %1$s* não era', p_n, v_pede));
      end if;
    elsif v_a.estado = 'agenda' then
      v_linhas := v_linhas || jsonb_build_array(format('   O cliente tem %s: %s. %s A dúvida é sua: responda pelo assistente, ou *não %s* se não era.',
        (case when v_k = 1 then '1 orçamento enviado' else v_k || ' orçamentos enviados' end), v_cands,
        (case when v_a.resultado ->> 'os_agenda' is not null
              then format('A agenda também espera resposta do cliente sobre a %s.', v_a.resultado ->> 'os_agenda')
              else 'A agenda também espera resposta do cliente.' end), p_n));
    else
      v_linhas := v_linhas || jsonb_build_array(format('   O cliente tem %s: %s. A dúvida é sua: responda pelo assistente, ou *não %s* se não era.',
        (case when v_k = 1 then '1 orçamento enviado' else v_k || ' orçamentos enviados' end), v_cands, p_n));
    end if;

    -- A OS em andamento do mesmo cliente: juntar é pela tela (agrupar_os, confirmação própria).
    select array_agg(so.service_order_number order by so.service_order_number) into v_and
      from public.service_orders so
     where so.client_id = v_a.client_id and so.merged_into_id is null
       and so.status in ('open', 'in_progress', 'awaiting_parts', 'awaiting_client', 'scheduled', 'approved');
    if cardinality(v_and) = 1 then
      v_linhas := v_linhas || jsonb_build_array(format('   A %s está em andamento: para juntar, use a tela.', v_and[1]));
    elsif cardinality(v_and) > 1 then
      v_linhas := v_linhas || jsonb_build_array(format('   As %s e %s estão em andamento: para juntar, use a tela.',
                                                       array_to_string(v_and[1:cardinality(v_and) - 1], ', '), v_and[cardinality(v_and)]));
    end if;
  end if;

  return jsonb_build_object(
    'tipo_item', 'aceite',
    'modelo_tipo', null,
    'service_order_id', v_a.service_order_id,
    'texto_mostrado', null,
    'opcoes', v_opcoes,
    'fatos', jsonb_build_object('total', v_so.grand_total, 'quote_status', v_so.quote_status, 'estado', v_a.estado),
    'linhas', v_linhas,
    'aceite_id', v_a.id,
    'rotulo', (case when p_abertura is null then public._orcamento_item_rotulo('aceite', v_a.id, null, 'lista') end),
    'hash', md5(concat_ws('|', v_a.id, v_a.estado, v_a.service_order_id, v_so.grand_total, v_so.quote_status, v_opcoes::text,
                          v_a.resultado ->> 'saida_nao_saiu')));
end;
$$;

comment on function public._orcamento_item_aceite(uuid, uuid, smallint, timestamptz) is
  'Retorno F5 (P7.1, C-ITEM-O): o item aceite (prioridade 3; p_abertura pode ser nulo). detectado: o orçamento (assunto, dia do envio), R$ e a validade do banco, letras A (aceite_com_sinal) e B (aceite_sem_sinal), e C/D (pedir_dados) com dados_nota_ligado e algo que o texto pede; duvida e agenda (com a OS da agenda): sem letra; o aviso do "Fechado" ou do pedido de dados que não saiu (resultado.saida_nao_saiu): sem letra, com o motivo. A OS em andamento do cliente ganha a linha "para juntar, use a tela". fatos = {total, quote_status, estado}; aceite_id; rotulo só sem caso.';

revoke all on function public._orcamento_item_aceite(uuid, uuid, smallint, timestamptz) from public, anon, authenticated;

-- Os dados da nota lidos da resposta do cliente: o CPF ou o CNPJ mascarado (só os 2 últimos dígitos), o CEP inteiro.
create or replace function public._orcamento_item_dados(p_abertura uuid, p_aceite uuid, p_n smallint, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_a public.orcamento_aceites;
  v_w record;
  v_doc text;
  v_cep text;
  v_lido text;
begin
  select * into v_a from public.orcamento_aceites a where a.id = p_aceite;
  select w.body, coalesce(w.hora_real, w.occurred_at) as quando into v_w from public.whatsapp_messages w where w.id = v_a.dados_msg_id;
  v_doc := public._orcamento_documento_lido(v_w.body);
  v_cep := public._orcamento_cep_lido(v_w.body);
  v_lido := concat_ws(' · ',
    (case when char_length(v_doc) = 11 then 'CPF •••.•••.•••-' || right(v_doc, 2) || ' (válido)'
          when char_length(v_doc) = 14 then 'CNPJ ••.•••.•••/••••-' || right(v_doc, 2) || ' (válido)' end),
    (case when v_cep is not null then 'CEP ' || substr(v_cep, 1, 5) || '-' || substr(v_cep, 6, 3) end));
  return jsonb_build_object(
    'tipo_item', 'dados_nota',
    'modelo_tipo', null,
    'service_order_id', v_a.service_order_id,
    'texto_mostrado', null,
    'opcoes', jsonb_build_array(jsonb_build_object('letra', 'A', 'acao', 'dados_gravar')),
    'fatos', jsonb_build_object('dados_msg_id', v_a.dados_msg_id, 'dados_estado', v_a.dados_estado),
    'linhas', jsonb_build_array(
      format('%s. %s · %s · respondeu ao pedido dos dados da nota · lido: %s', p_n,
             coalesce(public._retorno_nome(v_a.client_id), 'cliente sem nome'),
             coalesce(to_char(v_w.quando at time zone c_fuso, 'HH24:MI'), '--:--'), coalesce(nullif(v_lido, ''), 'nada')),
      format('   *%s A* grava na ficha o que está vazio · rua, bairro e cidade: pela tela', p_n)),
    'aceite_id', v_a.id,
    'rotulo', (case when p_abertura is null then public._orcamento_item_rotulo('dados_nota', v_a.id, null, 'lista') end),
    'hash', md5(concat_ws('|', v_a.id, v_a.dados_estado, v_a.dados_msg_id, v_lido)));
end;
$$;

comment on function public._orcamento_item_dados(uuid, uuid, smallint, timestamptz) is
  'Retorno F5 (P7.1, C-ITEM-O): o item dados_nota (prioridade 3; p_abertura pode ser nulo): "N. Ana · HH:MM · respondeu ao pedido dos dados da nota · lido: CPF •••.•••.•••-12 (válido) · CEP 88330-000" e "*N A* grava na ficha o que está vazio · rua, bairro e cidade: pela tela". Só os 2 últimos dígitos do documento; letra A (dados_gravar); aceite_id; rotulo só sem caso.';

revoke all on function public._orcamento_item_dados(uuid, uuid, smallint, timestamptz) from public, anon, authenticated;

-- ── 4. A conferência do item (o *sim <PIN>* vale sobre o que o dono leu) ─────────────────────────────────────────────────

-- stable: quem leva o aceite a 'caiu' é o executor (no *sim*) ou o bloco 7 do orcamento_vigia (o item que caiu pelo
-- retorno_vigia_cartao). O estado do caso não conta.
create or replace function public._orcamento_item_conferir(p_item uuid, p_agora timestamptz, p_executar boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_i public.retorno_cartao_itens;
  v_a public.orcamento_aceites;
  v_p public.orcamento_passos;
  v_ac public.orcamento_acompanhamentos;
  v_ab public.retorno_aberturas;
  v_numero text;
  v_quando timestamptz;
  v_cands uuid[];
  v_total numeric;
  v_m jsonb;
  v_motivo text;
  v_caiu text;
  v_quem jsonb;
  v_t jsonb;
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'caso_fechado', 'texto', 'o item já não existe; não mandei');
  end if;
  select so.service_order_number into v_numero from public.service_orders so where so.id = v_i.service_order_id;
  v_numero := coalesce(v_numero, 'orçamento');

  if v_i.tipo_item = 'cadencia' then
    select * into v_p from public.orcamento_passos p where p.id = v_i.passo_id;
    select * into v_ac from public.orcamento_acompanhamentos a where a.id = v_p.acompanhamento_id;
    if v_p.id is null or v_ac.id is null then
      return jsonb_build_object('ok', false, 'motivo', 'fato_mudou',
        'texto', format('o %s mudou desde o cartão: mande *retorno* para ver de novo; não mandei', v_i.n));
    end if;
    -- A parada, agora (C-PARAR): o cliente pode ter escrito depois de o cartão ser montado.
    v_m := public._orcamento_parar_motivo(v_ac.id, v_agora);
    v_motivo := coalesce(v_m ->> 'motivo',
                         (case when v_ac.estado = 'encerrado' then 'erro'
                               when v_ac.estado is distinct from 'ativo' then coalesce(v_ac.parou_por, 'status_mudou') end));
    if v_motivo is not null then
      -- A tabela de-para da P5.1 (caiu_motivo do item à espera).
      v_caiu := (case when v_motivo in ('cliente_escreveu', 'encerrou') then 'cliente_escreveu'
                      when v_motivo in ('parar', 'opt_out') then 'canal_bloqueado'
                      when v_motivo = 'dono_falou' then 'respondida_pelo_dono'
                      when v_motivo = 'segurado' then 'segurado'
                      when v_motivo in ('status_mudou', 'validade_mudou') then 'orcamento_mudou'
                      else 'fato_mudou' end);
      return jsonb_build_object('ok', false, 'motivo', v_caiu, 'texto', (case v_caiu
        when 'cliente_escreveu' then format('o %s caiu: o cliente escreveu depois do envio; não mandei', v_i.n)
        when 'canal_bloqueado' then format('o %s caiu: o cliente pediu para não receber mensagem automática; não mandei', v_i.n)
        when 'respondida_pelo_dono' then format('o %s caiu: você já escreveu ao cliente; não mandei', v_i.n)
        when 'segurado' then format('o %s caiu: os lembretes do %s estão segurados; não mandei', v_i.n, v_numero)
        when 'orcamento_mudou' then format('o %s caiu: o %s mudou desde o cartão; não mandei', v_i.n, v_numero)
        else format('o %s mudou desde o cartão: mande *retorno* para ver de novo; não mandei', v_i.n) end));
    end if;
    if p_executar then
      -- O passo ainda à espera e o texto de agora igual ao que o dono leu (a trava por hash da F2).
      v_t := public._orcamento_texto_do_passo(v_p.id, v_agora);
      if v_p.estado is distinct from 'aguarda_sim' or v_t ->> 'texto' is null or (v_t ->> 'texto') is distinct from v_i.texto_mostrado then
        return jsonb_build_object('ok', false, 'motivo', 'fato_mudou',
          'texto', format('o %s mudou desde o cartão: mande *retorno* para ver de novo; não mandei', v_i.n));
      end if;
    end if;
    return jsonb_build_object('ok', true);
  end if;

  -- O aceite e os dados da nota.
  select * into v_a from public.orcamento_aceites a where a.id = v_i.aceite_id;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'orcamento_mudou',
      'texto', format('o %s caiu: o aceite já não existe; não fiz nada', v_i.n));
  end if;
  if v_i.tipo_item = 'dados_nota' then
    if v_a.dados_estado is distinct from 'lidos' then
      return jsonb_build_object('ok', false, 'motivo', 'fato_mudou',
        'texto', format('o %s mudou desde o cartão: mande *retorno* para ver de novo; não fiz nada', v_i.n));
    end if;
  elsif v_a.estado in ('com_sinal', 'sem_sinal') and v_a.resultado ? 'saida_nao_saiu' then
    null;   -- o aviso do "Fechado" que não saiu: nada a conferir
  elsif v_a.estado in ('detectado', 'duvida', 'agenda') and v_a.executado_em is null then
    select coalesce(w.hora_real, w.occurred_at) into v_quando from public.whatsapp_messages w where w.id = v_a.whatsapp_message_id;
    v_cands := coalesce(public._orcamento_candidatos(v_a.client_id, v_a.chave, v_quando, v_agora), '{}'::uuid[]);
    if v_a.estado = 'detectado' then
      select so.grand_total into v_total from public.service_orders so where so.id = v_a.service_order_id;
      -- O orçamento deixou de ser candidato, sumiu ou mudou de total (desde a mensagem ou desde o cartão).
      if v_a.service_order_id is null or v_i.service_order_id is null or not (v_a.service_order_id = any (v_cands))
         or v_total is distinct from v_a.total_visto or v_total is distinct from (v_i.fatos ->> 'total')::numeric then
        return jsonb_build_object('ok', false, 'motivo', 'orcamento_mudou',
          'texto', format('o %s caiu: o %s mudou desde o cartão; não fiz nada', v_i.n, v_numero));
      end if;
    elsif not (coalesce(v_a.candidatos, '{}'::uuid[]) && v_cands) then
      return jsonb_build_object('ok', false, 'motivo', 'orcamento_mudou',
        'texto', format('o %s caiu: os orçamentos dele mudaram desde o cartão; não fiz nada', v_i.n));
    end if;
  else
    -- Decidido por outro caminho (o assistente, a tela, o vigia) depois de o cartão ser montado.
    return jsonb_build_object('ok', false,
      'motivo', (case when v_a.estado = 'caiu' and v_a.resultado ->> 'motivo' = 'pessoal' then 'canal_bloqueado'
                      when v_a.estado = 'caiu' then 'orcamento_mudou'
                      else 'fato_mudou' end),
      'texto', format('o %s mudou desde o cartão: mande *retorno* para ver de novo; não fiz nada', v_i.n));
  end if;

  -- O ditado (só com caso): as travas da F2 sobre o número.
  if v_i.texto_ditado is not null and v_i.abertura_id is not null then
    select * into v_ab from public.retorno_aberturas ab where ab.id = v_i.abertura_id;
    if v_ab.papel = 'cliente' then
      v_quem := public.quem_escreve(v_ab.phone_normalized);
      if (v_quem ->> 'cliente_id')::uuid is distinct from v_ab.client_id then
        return jsonb_build_object('ok', false, 'motivo', 'telefone_mudou', 'texto', format('o %s mudou de número; não mandei', v_i.n));
      end if;
    end if;
    if public.canal_bloqueado(v_ab.phone_normalized) is not null
       or exists (select 1 from public.whatsapp_leads l
                   where l.lead_tipo = 'pessoal' and public._agenda_chave_telefone(l.phone_normalized) = v_ab.chave) then
      return jsonb_build_object('ok', false, 'motivo', 'canal_bloqueado',
        'texto', format('o %s pediu para não receber mensagem automática: responda pelo celular se for preciso; não mandei', v_i.n));
    end if;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

comment on function public._orcamento_item_conferir(uuid, timestamptz, boolean) is
  'Retorno F5 (P7.1): a conferência do item do orçamento ({ok, motivo, texto}, como _retorno_item_conferir). aceite detectado: o orçamento ainda candidato e o total igual ao da mensagem (total_visto) e ao do cartão (fatos.total), senão orcamento_mudou; duvida/agenda: algum candidato ainda aberto; decidido por outro caminho: fato_mudou (caiu: orcamento_mudou; pessoal: canal_bloqueado); dados_nota: dados_estado lidos; com texto_ditado, as travas da F2 sobre o número (telefone_mudou, canal_bloqueado). cadencia: _orcamento_parar_motivo agora, pela tabela de-para da P5.1 (cliente_escreveu, canal_bloqueado, respondida_pelo_dono, segurado, orcamento_mudou, fato_mudou); com p_executar, o passo ainda aguarda_sim e o texto de agora igual a texto_mostrado. O estado do caso não conta.';

revoke all on function public._orcamento_item_conferir(uuid, timestamptz, boolean) from public, anon, authenticated;

-- ── 5. O *sim <PIN>*: o executor de cada item ───────────────────────────────────────────────────────────────────────────

-- O passo aprovado: o texto que o dono leu vai a texto_aprovado, e a saída nasce com por = 'sim' (é esse texto que sai).
create or replace function public._orcamento_passo_aprovar(p_passo uuid, p_item uuid, p_autor uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_texto text;
  v_saida uuid;
begin
  select i.texto_mostrado into v_texto from public.retorno_cartao_itens i where i.id = p_item;
  update public.orcamento_passos p
     set aprovado_em = p_agora, aprovado_por = p_autor, texto_aprovado = v_texto
   where p.id = p_passo and p.estado = 'aguarda_sim';
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'estado');
  end if;
  v_saida := public._orcamento_agendar_passo(p_passo, p_agora, 'sim');
  if v_saida is null then
    return jsonb_build_object('ok', false, 'motivo', coalesce((select p.motivo from public.orcamento_passos p where p.id = p_passo), 'erro'));
  end if;
  return jsonb_build_object('ok', true, 'saida_id', v_saida);
end;
$$;

comment on function public._orcamento_passo_aprovar(uuid, uuid, uuid, timestamptz) is
  'Retorno F5 (P7.1): o passo aguarda_sim aprovado no cartão: aprovado_em, aprovado_por e texto_aprovado (o texto_mostrado do item) e _orcamento_agendar_passo(…, sim). {ok, saida_id} ou {ok: false, motivo} (o passo já não esperava, ou não coube no prazo: o motivo do passo).';

revoke all on function public._orcamento_passo_aprovar(uuid, uuid, uuid, timestamptz) from public, anon, authenticated;

-- {frase, aceites, ditados, vai_sair, rotulo}; grava o estado do item. Erro nunca trava o cartão: A e C rodam num sub-bloco, e
-- a recusa de uma das duas chamadas desfaz a mudança de funil e derruba só o item.
create or replace function public._orcamento_item_executar(p_item uuid, p_autor uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_vazio constant jsonb := jsonb_build_object('frase', null, 'aceites', '[]'::jsonb, 'ditados', '[]'::jsonb, 'vai_sair', false,
                                               'rotulo', null);
  v_i public.retorno_cartao_itens;
  v_a public.orcamento_aceites;
  v_ab public.retorno_aberturas;
  v_conf jsonb;
  v_r1 jsonb;
  v_r2 jsonb;
  v_numero text;
  v_nome text;
  v_pedir boolean;
  v_rotulo text;
  v_lista text[];
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item for update;
  if not found or v_i.estado is distinct from 'vivo' then
    return v_vazio;
  end if;

  -- 1. A conferência (pelo _retorno_item_conferir, que despacha para a da F5).
  v_conf := public._retorno_item_conferir(v_i.id, v_agora, true);
  if not coalesce((v_conf ->> 'ok')::boolean, false) then
    update public.retorno_cartao_itens i
       set estado = 'caiu', caiu_motivo = v_conf ->> 'motivo', decidido_em = v_agora
     where i.id = v_i.id;
    if v_i.tipo_item = 'aceite' and v_conf ->> 'motivo' = 'orcamento_mudou' then
      update public.orcamento_aceites a
         set estado = 'caiu', decidido_em = v_agora,
             resultado = a.resultado || jsonb_build_object(
               'motivo', 'orcamento_mudou', 'total_antes', a.total_visto,
               'total_agora', (select so.grand_total from public.service_orders so where so.id = a.service_order_id))
       where a.id = v_i.aceite_id and a.estado in ('detectado', 'duvida', 'agenda') and a.executado_em is null;
    end if;
    return v_vazio || jsonb_build_object('frase', v_conf ->> 'texto');
  end if;

  select * into v_a from public.orcamento_aceites a where a.id = v_i.aceite_id;
  select so.service_order_number into v_numero from public.service_orders so
   where so.id = coalesce(v_a.service_order_id, v_i.service_order_id);
  v_numero := coalesce(v_numero, 'orçamento');
  v_nome := coalesce(public._retorno_nome(v_a.client_id), 'o cliente');

  -- 2. A cadência: aprovado, a saída nasce com o texto que o dono leu.
  if v_i.tipo_item = 'cadencia' then
    v_r1 := public._orcamento_passo_aprovar(v_i.passo_id, v_i.id, p_autor, v_agora);
    if not coalesce((v_r1 ->> 'ok')::boolean, false) then
      update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = 'fato_mudou', decidido_em = v_agora where i.id = v_i.id;
      return v_vazio || jsonb_build_object('frase', (case when v_r1 ->> 'motivo' = 'fora_da_janela'
                                                           then format('o %s não cabe mais no prazo dele; não mandei', v_i.n)
                                                           else format('o %s não saiu; não mandei', v_i.n) end));
    end if;
    update public.retorno_cartao_itens i
       set estado = 'feito', decidido_em = v_agora, saida_id = (v_r1 ->> 'saida_id')::uuid
     where i.id = v_i.id;
    v_rotulo := public._orcamento_item_rotulo('cadencia', null, v_i.passo_id, 'dono');
    if public._orcamento_modo_efetivo((v_r1 ->> 'saida_id')::uuid, v_agora) = 'ligado' then
      return v_vazio || jsonb_build_object('vai_sair', true, 'rotulo', v_rotulo);
    end if;
    -- O retorno ou o orçamento em teste: a saída fica em sombra (só medida), e o dono sabe que não vai ao cliente.
    return v_vazio || jsonb_build_object('frase', format('o %s fica em teste: %s não vai ao cliente', v_i.n, v_rotulo));
  end if;

  -- 3. O ditado (só com caso; o T-DIT-1 recusa sem caso): sai pelo caso, no formato da F2. O aceite fica 'respondido' (os
  --    dados, 'nada') quando o envio volta com p_ok (retorno_item_enviado, T-ENV-1).
  if v_i.texto_ditado is not null then
    select * into v_ab from public.retorno_aberturas ab where ab.id = v_i.abertura_id;
    if not found then
      update public.retorno_cartao_itens i set estado = 'fora', decidido_em = v_agora where i.id = v_i.id;
      return v_vazio || jsonb_build_object('frase', format('o %s não tem conversa aberta: responda pelo assistente', v_i.n));
    end if;
    update public.retorno_cartao_itens i set estado = 'feito', decidido_em = v_agora where i.id = v_i.id;
    return v_vazio || jsonb_build_object(
      'ditados', jsonb_build_array(jsonb_build_object('item_id', v_i.id, 'phone', v_ab.phone_normalized, 'texto', v_i.texto_ditado,
                                                      'dedupe_key', 'retorno:' || v_ab.id || ':ditado:' || md5(v_i.texto_ditado))),
      'vai_sair', true,
      'rotulo', public._retorno_rotulo(v_ab.id, v_agora),
      'frase', (case when v_i.tipo_item = 'aceite' and v_a.estado in ('detectado', 'duvida', 'agenda')
                     then format('o %s: mandei o seu texto a %s; o %s ficou como estava (converta pela tela ou pelo assistente)',
                                 v_i.n, v_nome, v_numero) end));
  end if;

  -- 4. O aviso do "Fechado" (ou do pedido de dados) que não saiu: visto, sai da lista (volta uma vez só).
  if v_i.tipo_item = 'aceite' and v_a.estado in ('com_sinal', 'sem_sinal') and v_a.resultado ? 'saida_nao_saiu' then
    update public.orcamento_aceites a
       set resultado = a.resultado || jsonb_build_object('nao_saiu_fechado_em', v_agora)
     where a.id = v_a.id and not (a.resultado ? 'nao_saiu_fechado_em');
    update public.retorno_cartao_itens i set estado = 'fora', decidido_em = v_agora where i.id = v_i.id;
    return v_vazio || jsonb_build_object('frase', format('o %s: o aviso saiu da lista; responder ao cliente fica com você', v_i.n));
  end if;

  -- 5. Os dados da nota: A grava na ficha só o que está vazio.
  if v_i.tipo_item = 'dados_nota' then
    if v_i.escolha is distinct from 'A' then
      update public.retorno_cartao_itens i set estado = 'fora', decidido_em = v_agora where i.id = v_i.id;
      return v_vazio || jsonb_build_object('frase', format('o %s ficou sem letra: continua na lista', v_i.n));
    end if;
    v_r1 := public.orcamento_dados_gravar(v_a.id, p_autor, v_agora);
    if not coalesce((v_r1 ->> 'ok')::boolean, false) then
      update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = 'fato_mudou', decidido_em = v_agora where i.id = v_i.id;
      return v_vazio || jsonb_build_object('frase', format('o %s caiu: os dados já não estão para gravar; nada mudou', v_i.n));
    end if;
    update public.retorno_cartao_itens i set estado = 'feito', decidido_em = v_agora where i.id = v_i.id;
    select array_agg(x.v order by x.i) into v_lista
      from jsonb_array_elements_text(coalesce(v_r1 -> 'gravou', '[]'::jsonb)) with ordinality as x(v, i);
    if cardinality(v_lista) > 0 then
      return v_vazio || jsonb_build_object('frase', format('Gravei na ficha de %s: %s.', v_nome,
        (case when cardinality(v_lista) = 1 then v_lista[1]
              else array_to_string(v_lista[1:cardinality(v_lista) - 1], ', ') || ' e ' || v_lista[cardinality(v_lista)] end)));
    end if;
    return v_vazio || jsonb_build_object('frase', format('A ficha de %s já tinha esses dados: nada mudou.', v_nome));
  end if;

  -- 6. O aceite. Sem letra (selecionado sem escolha, ou duvida/agenda): fora, e volta no próximo *retorno*.
  if v_i.escolha is null or v_a.estado is distinct from 'detectado' then
    update public.retorno_cartao_itens i set estado = 'fora', decidido_em = v_agora where i.id = v_i.id;
    return v_vazio || jsonb_build_object('frase', (case when jsonb_array_length(v_i.opcoes) > 0
                                                         then format('o %s ficou sem letra: continua na lista', v_i.n) end));
  end if;
  v_pedir := v_i.escolha in ('C', 'D');

  if v_i.escolha in ('A', 'C') then
    -- Aprovado, aguardando o sinal, e registrado na mesma transação (o "Fechado" agendado): o vigia nunca vê o aceite
    -- 'detectado' com o orçamento em awaiting_deposit. Uma recusa desfaz as duas.
    begin
      v_r1 := public.orcamento_aceite_com_sinal(v_a.id, p_autor, v_agora);
      if not coalesce((v_r1 ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0001', message = 'f5_aceite_recusado', detail = coalesce(v_r1 ->> 'motivo', 'erro');
      end if;
      v_r2 := public.orcamento_aceite_registrar(v_a.id, true,
                jsonb_build_object('escolha', 'com_sinal', 'numero', v_r1 ->> 'numero', 'quote_status', v_r1 ->> 'quote_status'),
                p_autor, v_pedir, v_agora);
      if not coalesce((v_r2 ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0001', message = 'f5_aceite_recusado', detail = coalesce(v_r2 ->> 'motivo', 'erro');
      end if;
    exception when others then
      if sqlerrm is distinct from 'f5_aceite_recusado' then
        perform public._retorno_log('orcamento_cartao', '_orcamento_item_executar: ' || sqlerrm, 'error',
                                    jsonb_build_object('item_id', v_i.id, 'aceite_id', v_a.id, 'sqlstate', sqlstate));
      end if;
      update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = 'fato_mudou', decidido_em = v_agora where i.id = v_i.id;
      return v_vazio || jsonb_build_object('frase', format('o %s caiu: não consegui registrar o aceite; nada mudou', v_i.n));
    end;
    update public.retorno_cartao_itens i set estado = 'feito', decidido_em = v_agora where i.id = v_i.id;
    return v_vazio || jsonb_build_object('aceites', jsonb_build_array(jsonb_build_object(
      'item_id', v_i.id, 'aceite_id', v_a.id, 'service_order_id', v_a.service_order_id, 'escolha', 'com_sinal', 'feito', true,
      'registrado', jsonb_build_object('fechado', v_r2 -> 'fechado', 'dados', v_r2 -> 'dados'),
      'pedir_dados', v_pedir, 'total_visto', v_a.total_visto, 'msg_id', v_a.whatsapp_message_id,
      'numero', v_r1 ->> 'numero', 'quote_status', v_r1 ->> 'quote_status')));
  end if;

  -- B ou D: a conversão sem sinal é da ferramenta (a condição "100% na entrega" tem fonte única em TS). executado_em faz o
  -- vigia esperar por ela (P3.1, bloco 7).
  update public.orcamento_aceites a
     set executado_em = v_agora, decidido_por = p_autor
   where a.id = v_a.id and a.estado = 'detectado' and a.executado_em is null;
  if not found then
    update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = 'fato_mudou', decidido_em = v_agora where i.id = v_i.id;
    return v_vazio || jsonb_build_object('frase', format('o %s mudou desde o cartão: mande *retorno* para ver de novo; não fiz nada', v_i.n));
  end if;
  update public.retorno_cartao_itens i set estado = 'feito', decidido_em = v_agora where i.id = v_i.id;
  return v_vazio || jsonb_build_object('aceites', jsonb_build_array(jsonb_build_object(
    'item_id', v_i.id, 'aceite_id', v_a.id, 'service_order_id', v_a.service_order_id, 'escolha', 'sem_sinal',
    'pedir_dados', v_pedir, 'total_visto', v_a.total_visto, 'msg_id', v_a.whatsapp_message_id, 'numero', v_numero)));
end;
$$;

comment on function public._orcamento_item_executar(uuid, uuid, timestamptz) is
  'Retorno F5 (P7.1, C-EXEC): o *sim <PIN>* num item do orçamento. Conferência falhou → item caiu (aceite com orcamento_mudou → aceite caiu). cadencia → _orcamento_passo_aprovar (vai_sair com "o lembrete do ORÇ-… (Ana)", ou "fica em teste" quando o modo efetivo é sombra). Ditado (só com caso) → ditados no formato da F2, vai_sair. Aviso do que não saiu → resultado.nao_saiu_fechado_em, item fora. dados_nota A → orcamento_dados_gravar. aceite sem letra (ou duvida/agenda) → fora. A/C → orcamento_aceite_com_sinal + orcamento_aceite_registrar(com_sinal) num sub-bloco (recusa: item caiu, nada muda); B/D → executado_em e decidido_por (a ferramenta converte e registra). {frase, aceites, ditados, vai_sair, rotulo}.';

revoke all on function public._orcamento_item_executar(uuid, uuid, timestamptz) from public, anon, authenticated;

-- ── 6. As palavras do dono no item do orçamento ─────────────────────────────────────────────────────────────────────────

-- Os itens do orçamento tirados com *não N* (tirado_em e selecionado = false): aceite nao_era, dados nada, passo
-- pulado/tirado. O que ficou de fora por *só*/*sem* vai a 'fora' como na F2 e volta no próximo *retorno*; o aviso do que não
-- saiu, fora da seleção por qualquer caminho, sai da lista (volta uma vez só).
create or replace function public._orcamento_cartao_tirados(p_cartao uuid, p_agora timestamptz)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_dono uuid := (select d.id from public._comprovante_dono() d);
  v_r record;
  v_n integer := 0;
begin
  for v_r in
    select i.id, i.tipo_item, i.aceite_id, i.passo_id, i.tirado_em
      from public.retorno_cartao_itens i
     where i.cartao_id = p_cartao and i.estado = 'vivo' and not i.selecionado
       and i.tipo_item in ('aceite', 'dados_nota', 'cadencia')
     order by i.n
  loop
    if v_r.tipo_item = 'aceite' then
      update public.orcamento_aceites a
         set resultado = a.resultado || jsonb_build_object('nao_saiu_fechado_em', v_agora)
       where a.id = v_r.aceite_id and a.estado in ('com_sinal', 'sem_sinal') and a.resultado ? 'saida_nao_saiu'
         and not (a.resultado ? 'nao_saiu_fechado_em');
      if found then
        v_n := v_n + 1;
        continue;
      end if;
    end if;
    continue when v_r.tirado_em is null;
    if v_r.tipo_item = 'aceite' then
      update public.orcamento_aceites a
         set estado = 'nao_era', decidido_em = v_agora, decidido_por = v_dono
       where a.id = v_r.aceite_id and a.estado in ('detectado', 'duvida', 'agenda') and a.executado_em is null;
      if found then
        perform public._orcamento_aceite_fechar_antigos(v_r.aceite_id, v_agora);
        v_n := v_n + 1;
      end if;
    elsif v_r.tipo_item = 'dados_nota' then
      update public.orcamento_aceites a set dados_estado = 'nada'
       where a.id = v_r.aceite_id and a.dados_estado = 'lidos';
      if found then
        v_n := v_n + 1;
      end if;
    else
      update public.orcamento_passos p set estado = 'pulado', motivo = 'tirado'
       where p.id = v_r.passo_id and p.estado = 'aguarda_sim';
      if found then
        v_n := v_n + 1;
      end if;
    end if;
  end loop;
  return v_n;
end;
$$;

comment on function public._orcamento_cartao_tirados(uuid, timestamptz) is
  'Retorno F5 (P7.1): antes de os itens não selecionados irem a fora (o *sim <PIN>* ou o cartão que fecha porque nada ficou selecionado), o desfecho dos itens do orçamento tirados com *não N* (tirado_em, selecionado = false): aceite nao_era (decidido pelo dono, e _orcamento_aceite_fechar_antigos), dados nada, passo pulado/tirado. De fora por *só*/*sem* (tirado_em nulo): nada muda, volta no próximo *retorno*. O aviso do que não saiu fora da seleção ganha resultado.nao_saiu_fechado_em. Devolve quantos teve desfecho.';

revoke all on function public._orcamento_cartao_tirados(uuid, timestamptz) from public, anon, authenticated;

-- A letra do item de aceite ou de dados da nota. Vale o último comando: a letra apaga o ditado (e o *dita* apaga a letra).
create or replace function public._orcamento_decidir_letra(p_item public.retorno_cartao_itens, p_comando jsonb, p_dono uuid,
                                                           p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_letra text := upper(coalesce(p_comando ->> 'letra', ''));
  v_resto text := nullif(btrim(coalesce(p_comando ->> 'resto', '')), '');
  v_op jsonb;
  v_a public.orcamento_aceites;
  v_numero text;
  v_nome text;
  v_faltas text[];
  v_doc boolean;
  v_end boolean;
  v_empresa boolean;
  v_pede text;
  v_texto text;
begin
  select o into v_op from jsonb_array_elements(p_item.opcoes) o where o ->> 'letra' = v_letra limit 1;
  if v_op is null then
    return jsonb_build_object('ok', true, 'texto', format('O %s não tem a opção %s, e nada foi feito.', p_item.n, v_letra));
  end if;
  if v_resto is not null then
    return jsonb_build_object('ok', true, 'texto', format('A letra do %s vai sozinha: *%s %s*.', p_item.n, p_item.n, v_letra));
  end if;

  update public.retorno_cartao_itens i
     set escolha = v_letra, selecionado = true, texto_ditado = null, ditado_via = null
   where i.id = p_item.id;
  update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = p_item.cartao_id;

  select * into v_a from public.orcamento_aceites a where a.id = p_item.aceite_id;
  v_nome := coalesce(public._retorno_nome(v_a.client_id), 'o cliente');
  select so.service_order_number into v_numero from public.service_orders so
   where so.id = coalesce(p_item.service_order_id, v_a.service_order_id);
  v_numero := coalesce(v_numero, 'orçamento');

  if p_item.tipo_item = 'dados_nota' then
    v_texto := format('Anotei *%s A*: gravo na ficha de %s só o que está vazio. *sim <PIN>* faz.', p_item.n, v_nome);
  else
    -- O que pedir com C e D: as mesmas faltas do O17–O20 ("o CNPJ" na empresa; só o documento ou só o endereço).
    v_faltas := coalesce(public._orcamento_faltas_para_nota(v_a.client_id), '{}'::text[]);
    v_doc := v_faltas && array['CPF/CNPJ', 'CPF/CNPJ incompleto'];
    v_end := v_faltas && array['rua', 'bairro', 'cidade', 'UF', 'CEP', 'CEP incompleto'];
    select c.type = 'company' into v_empresa from public.clients c where c.id = v_a.client_id;
    v_pede := (case when v_doc and v_end then (case when coalesce(v_empresa, false) then 'o CNPJ e o endereço' else 'o CPF e o endereço' end)
                    when v_doc then (case when coalesce(v_empresa, false) then 'o CNPJ' else 'o CPF' end)
                    when v_end then 'o endereço'
                    else 'os dados da nota' end);
    v_texto := (case v_letra
      when 'A' then format('Anotei *%s A*: o %s fica aprovado, aguardando o sinal. *sim <PIN>* faz.', p_item.n, v_numero)
      when 'B' then format('Anotei *%s B*: converto o %s em OS sem sinal e mando o ''Fechado'' a %s. *sim <PIN>* faz.', p_item.n, v_numero, v_nome)
      when 'C' then format('Anotei *%s C*: o %s fica aprovado, aguardando o sinal, e peço a %s %s. *sim <PIN>* faz.', p_item.n, v_numero, v_nome, v_pede)
      else format('Anotei *%s D*: converto o %s em OS sem sinal, mando o ''Fechado'' e peço a %s %s. *sim <PIN>* faz.', p_item.n, v_numero, v_nome, v_pede)
    end);
  end if;
  if p_item.texto_ditado is not null then
    v_texto := v_texto || ' O texto que você ditou saiu do item.';
  end if;
  return jsonb_build_object('ok', true, 'precisa_pin', true, 'texto', v_texto);
end;
$$;

comment on function public._orcamento_decidir_letra(public.retorno_cartao_itens, jsonb, uuid, timestamptz) is
  'Retorno F5 (P7.1): a letra do item aceite ou dados_nota. Letra que o item não tem: "O N não tem a opção X, e nada foi feito." (sem precisa_pin); letra com resto: "A letra do N vai sozinha: *N X*."; senão grava escolha e selecionado, apaga texto_ditado e ditado_via (vale o último comando), remonta o texto do cartão e responde a frase da letra com precisa_pin (" O texto que você ditou saiu do item." quando havia ditado).';

revoke all on function public._orcamento_decidir_letra(public.retorno_cartao_itens, jsonb, uuid, timestamptz) from public, anon, authenticated;

-- *ver N* no item do orçamento: com caso, as mensagens do caso; sem caso, a mensagem do aceite (e a dos dados); no passo, o
-- texto inteiro e os outros passos. Depois, o resto das linhas do item.
create or replace function public._orcamento_ver_item(p_item uuid, p_autor uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_i public.retorno_cartao_itens;
  v_c public.retorno_cartoes;
  v_a public.orcamento_aceites;
  v_p public.orcamento_passos;
  v_cab text;
  v_corpo text;
  v_extras text;
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item;
  select * into v_c from public.retorno_cartoes c where c.id = v_i.cartao_id;
  select regexp_replace(l.linha, '^[0-9]+\. ', '') into v_cab
    from jsonb_array_elements_text(coalesce(v_c.dados -> 'linhas' -> v_i.n::text, '[]'::jsonb)) with ordinality as l(linha, ord)
   where l.ord = 1;

  if v_i.tipo_item = 'cadencia' then
    select * into v_p from public.orcamento_passos p where p.id = v_i.passo_id;
    select string_agg(format('%s %s (%s)', (case x.passo when 'vespera' then 'véspera' else x.passo end), public._dia_curto(x.dia),
                             (case x.estado when 'previsto' then 'previsto' when 'aguarda_sim' then 'à espera do sim'
                                            when 'agendado' then 'agendado' when 'enviado' then 'enviado' when 'sombra' then 'em teste'
                                            when 'pulado' then 'não saiu' else 'cancelado' end)), ' · ' order by x.dia, x.passo)
      into v_extras
      from public.orcamento_passos x where x.acompanhamento_id = v_p.acompanhamento_id;
    v_corpo := concat_ws(E'\n', format('Texto inteiro: ''%s''', coalesce(v_i.texto_mostrado, '(o texto não se montou)')),
                         'Os passos: ' || v_extras);
  else
    select * into v_a from public.orcamento_aceites a where a.id = v_i.aceite_id;
    if v_i.abertura_id is not null then
      select string_agg(x.linha, E'\n' order by x.recebida_em, x.id)
        into v_corpo
        from (select m.recebida_em, m.whatsapp_message_id as id,
                     to_char(m.recebida_em at time zone c_fuso, 'HH24:MI') || ' '
                       || public._retorno_trecho(w.body, w.message_type, m.audio_pendente, 300) as linha
                from public.retorno_mensagens m
                join public.whatsapp_messages w on w.id = m.whatsapp_message_id
               where m.abertura_id = v_i.abertura_id and m.recebida_em <= v_agora
               order by m.recebida_em desc, m.whatsapp_message_id desc
               limit 5) x;
    else
      select string_agg(x.linha, E'\n' order by x.quando, x.id)
        into v_corpo
        from (select coalesce(w.hora_real, w.occurred_at) as quando, w.id,
                     to_char(coalesce(w.hora_real, w.occurred_at) at time zone c_fuso, 'HH24:MI') || ' '
                       || public._retorno_trecho(w.body, w.message_type,
                                                 (select rm.audio_pendente from public.retorno_mensagens rm where rm.whatsapp_message_id = w.id),
                                                 300) as linha
                from public.whatsapp_messages w
               where w.id in (v_a.whatsapp_message_id, v_a.dados_msg_id)) x;
    end if;
    select string_agg(btrim(l.linha), E'\n' order by l.ord)
      into v_extras
      from jsonb_array_elements_text(coalesce(v_c.dados -> 'linhas' -> v_i.n::text, '[]'::jsonb)) with ordinality as l(linha, ord)
     where l.ord > 1;
    v_corpo := concat_ws(E'\n', v_corpo, v_extras);
  end if;

  perform public._retorno_toque('ver', v_i.cartao_id, v_i.abertura_id, v_agora);
  return jsonb_build_object('ok', true,
    'texto', concat_ws(E'\n', v_cab, v_corpo),
    'historico', jsonb_build_object('user', format('(ver %s)', v_i.n), 'assistant', format('(mostrei o item %s ao dono)', v_i.n)));
end;
$$;

comment on function public._orcamento_ver_item(uuid, uuid, timestamptz) is
  'Retorno F5 (P7.1): o *ver N* do item do orçamento: a 1ª linha do item (sem o número); cadência: o texto inteiro e os passos do acompanhamento; aceite e dados: com caso, as últimas 5 mensagens do caso (como a F2), sem caso, a mensagem do aceite e a dos dados, e as outras linhas do item. O trecho do cliente vai só ao WhatsApp do dono; o histórico da conversa leva só o número do item.';

revoke all on function public._orcamento_ver_item(uuid, uuid, timestamptz) from public, anon, authenticated;

-- *resolvido N*: cadência → passo pulado/tirado; aceite → nao_era (o aviso: visto); dados → nada. Sem caso, faz o que a F2
-- faria com o item e responde com o rótulo do orçamento; com caso, devolve {ok} e a F2 segue (fecha o caso).
create or replace function public._orcamento_item_resolvido(p_item uuid, p_autor uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_i public.retorno_cartao_itens;
  v_antes jsonb;
  v_depois jsonb;
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item for update;
  if not found then
    return jsonb_build_object('ok', true, 'texto', 'Esse item já não está na lista. Mande *retorno*.');
  end if;
  if v_i.tipo_item = 'cadencia' then
    select jsonb_build_object('passo', p.estado, 'passo_id', p.id) into v_antes from public.orcamento_passos p where p.id = v_i.passo_id;
    update public.orcamento_passos p set estado = 'pulado', motivo = 'tirado'
     where p.id = v_i.passo_id and p.estado = 'aguarda_sim';
    v_depois := jsonb_build_object('passo', 'pulado', 'motivo', 'tirado', 'passo_id', v_i.passo_id);
  elsif v_i.tipo_item = 'aceite' then
    select jsonb_build_object('aceite', a.estado, 'aceite_id', a.id) into v_antes from public.orcamento_aceites a where a.id = v_i.aceite_id;
    update public.orcamento_aceites a
       set resultado = a.resultado || jsonb_build_object('nao_saiu_fechado_em', p_agora)
     where a.id = v_i.aceite_id and a.estado in ('com_sinal', 'sem_sinal') and a.resultado ? 'saida_nao_saiu'
       and not (a.resultado ? 'nao_saiu_fechado_em');
    update public.orcamento_aceites a
       set estado = 'nao_era', decidido_em = p_agora, decidido_por = p_autor
     where a.id = v_i.aceite_id and a.estado in ('detectado', 'duvida', 'agenda') and a.executado_em is null;
    if found then
      perform public._orcamento_aceite_fechar_antigos(v_i.aceite_id, p_agora);
    end if;
    v_depois := jsonb_build_object('aceite', 'nao_era', 'aceite_id', v_i.aceite_id);
  else
    select jsonb_build_object('dados', a.dados_estado, 'aceite_id', a.id) into v_antes from public.orcamento_aceites a where a.id = v_i.aceite_id;
    update public.orcamento_aceites a set dados_estado = 'nada' where a.id = v_i.aceite_id and a.dados_estado = 'lidos';
    v_depois := jsonb_build_object('dados', 'nada', 'aceite_id', v_i.aceite_id);
  end if;

  if v_i.abertura_id is not null then
    return jsonb_build_object('ok', true);
  end if;
  update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = 'caso_fechado', decidido_em = p_agora where i.id = v_i.id;
  update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = v_i.cartao_id;
  perform public._retorno_auditar_palavra(p_autor, v_antes, v_depois, '*resolvido* do dono');
  perform public._retorno_toque('resolvido', v_i.cartao_id, null, p_agora);
  return jsonb_build_object('ok', true,
    'texto', format('%s: resolvido, saiu da lista.', public._orcamento_item_rotulo(v_i.tipo_item, v_i.aceite_id, v_i.passo_id, 'dono')));
end;
$$;

comment on function public._orcamento_item_resolvido(uuid, uuid, timestamptz) is
  'Retorno F5 (P7.1): *resolvido N* no item do orçamento. cadencia → passo pulado/tirado; aceite → nao_era (decidido pelo dono, e _orcamento_aceite_fechar_antigos; o aviso do que não saiu: nao_saiu_fechado_em); dados_nota → nada. Sem caso: item caiu/caso_fechado, texto do cartão remontado, _retorno_auditar_palavra e _retorno_toque, e "o lembrete do ORÇ-… (Ana): resolvido, saiu da lista."; com caso: {ok} (a F2 segue e fecha o caso).';

revoke all on function public._orcamento_item_resolvido(uuid, uuid, timestamptz) from public, anon, authenticated;

-- *pessoal N* no item do orçamento com caso (o T-PES-1 recusa sem caso): o número virou pessoal, o aceite cai (os antigos do
-- mesmo cliente também); os dados, nada.
create or replace function public._orcamento_item_pessoal(p_item uuid, p_agora timestamptz)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_i public.retorno_cartao_itens;
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item;
  if not found or v_i.aceite_id is null then
    return;
  end if;
  if v_i.tipo_item = 'dados_nota' then
    update public.orcamento_aceites a set dados_estado = 'nada' where a.id = v_i.aceite_id and a.dados_estado = 'lidos';
    return;
  end if;
  update public.orcamento_aceites a
     set resultado = a.resultado || jsonb_build_object('nao_saiu_fechado_em', p_agora)
   where a.id = v_i.aceite_id and a.estado in ('com_sinal', 'sem_sinal') and a.resultado ? 'saida_nao_saiu'
     and not (a.resultado ? 'nao_saiu_fechado_em');
  update public.orcamento_aceites a
     set estado = 'caiu', decidido_em = p_agora, decidido_por = (select d.id from public._comprovante_dono() d),
         resultado = a.resultado || jsonb_build_object('motivo', 'pessoal')
   where a.id = v_i.aceite_id and a.estado in ('detectado', 'duvida', 'agenda') and a.executado_em is null;
  if found then
    perform public._orcamento_aceite_fechar_antigos(v_i.aceite_id, p_agora);
  end if;
end;
$$;

comment on function public._orcamento_item_pessoal(uuid, timestamptz) is
  'Retorno F5 (P7.1): *pessoal N* num item de aceite ou de dados com caso. aceite → caiu (resultado.motivo = pessoal, decidido pelo dono) e _orcamento_aceite_fechar_antigos (os antigos do mesmo cliente caem por pessoal); o aviso do que não saiu: nao_saiu_fechado_em; dados_nota → nada.';

revoke all on function public._orcamento_item_pessoal(uuid, timestamptz) from public, anon, authenticated;

-- O ditado do dono saiu (retorno_item_enviado com p_ok): o aceite fica respondido (o orçamento como está); os dados, nada.
create or replace function public._orcamento_ditado_enviado(p_item uuid, p_agora timestamptz)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_i public.retorno_cartao_itens;
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item;
  if not found or v_i.aceite_id is null then
    return;
  end if;
  if v_i.tipo_item = 'dados_nota' then
    update public.orcamento_aceites a set dados_estado = 'nada' where a.id = v_i.aceite_id and a.dados_estado = 'lidos';
    return;
  end if;
  update public.orcamento_aceites a
     set resultado = a.resultado || jsonb_build_object('nao_saiu_fechado_em', p_agora)
   where a.id = v_i.aceite_id and a.estado in ('com_sinal', 'sem_sinal') and a.resultado ? 'saida_nao_saiu'
     and not (a.resultado ? 'nao_saiu_fechado_em');
  update public.orcamento_aceites a
     set estado = 'respondido', decidido_em = p_agora, decidido_por = (select d.id from public._comprovante_dono() d),
         resultado = a.resultado || jsonb_build_object('ditado', true)
   where a.id = v_i.aceite_id and a.estado in ('detectado', 'duvida', 'agenda') and a.executado_em is null;
  if found then
    perform public._orcamento_aceite_fechar_antigos(v_i.aceite_id, p_agora);
  end if;
end;
$$;

comment on function public._orcamento_ditado_enviado(uuid, timestamptz) is
  'Retorno F5 (P7.1): o ditado do dono num item de aceite ou de dados saiu (T-ENV-1). aceite → respondido (decidido pelo dono, resultado.ditado = true) e _orcamento_aceite_fechar_antigos; o orçamento fica como está; o aviso do que não saiu: nao_saiu_fechado_em; dados_nota → nada.';

revoke all on function public._orcamento_ditado_enviado(uuid, timestamptz) from public, anon, authenticated;

-- ── 7. As geradas (corpo vigente + os trechos -- F5) ────────────────────────────────────────────────────────────────────

create or replace function public.retorno_cartao_abrir(p_gatilho text, p_agora timestamptz default now(), p_aviso uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (v_agora at time zone c_fuso)::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_vivo jsonb;
  v_cartao uuid;
  v_total integer;
  v_mais integer;
  v_n smallint := 0;
  v_caso record;
  v_item jsonb;
  v_linhas jsonb := '{}'::jsonb;
  v_hashes text := '';
  v_rotulos text[] := '{}';
  v_nomes text[] := '{}';
  v_texto text;
  v_k integer;
  v_dono uuid;
  v_phone text;
  v_o jsonb;
  v_ocupado boolean;
  v_sessao uuid;
  v_pend uuid;
  v_perg jsonb;
  v_expira timestamptz;
  v_chave_aviso text;
begin
  if v_cfg.id is null or v_cfg.modo = 'desligado' or p_gatilho is null or p_gatilho not in ('puxar', 'meio_dia', 'acorde') then
    return jsonb_build_object('acao', 'vazio');
  end if;
  perform pg_advisory_xact_lock(hashtext('retorno:cartao'));

  v_vivo := public.retorno_cartao_vivo(v_agora);
  -- Revisão da F3: cartão vivo sem item não reapresenta nem prende os casos novos: fecha, e segue como se não houvesse cartão.
  if v_vivo ->> 'estado' = 'vivo' and public._retorno_cartao_fechar_se_vazio((v_vivo ->> 'id')::uuid, v_agora) then
    v_vivo := null;
  end if;
  if v_vivo is not null and v_vivo ->> 'estado' = 'vivo' then
    v_cartao := (v_vivo ->> 'id')::uuid;
    if p_gatilho = 'puxar' then
      update public.retorno_cartao_itens i set selecionado = true where i.cartao_id = v_cartao and i.estado = 'vivo';
      -- F3 (P5): é o que faz a unidade recém-criada aparecer no *retorno*. Item com acao_sim não remonta: o *sim <PIN>* vale sobre o que o dono leu.
      if v_cfg.previa_ditado_ligado or v_cfg.previa_modo = 'ligado' then
        for v_caso in
          select i.id from public.retorno_cartao_itens i
           where i.cartao_id = v_cartao and i.estado = 'vivo' and i.tipo_item in ('orcamento', 'adicional', 'numero_novo')
             and i.acao_sim is null and i.escolha is null and i.texto_ditado is null
        loop
          perform public._retorno_item_remontar(v_caso.id, v_agora);
        end loop;
      end if;
      v_texto := public._retorno_cartao_texto(v_cartao, null);
      update public.retorno_cartoes c set texto = v_texto where c.id = v_cartao;
      return jsonb_build_object('acao', 'reapresenta', 'cartao_id', v_cartao, 'texto', v_texto);
    elsif p_gatilho = 'meio_dia' then
      select count(*) into v_k
        from public.retorno_aberturas a
       where a.estado in ('aberta', 'vencida') and a.cumprida_em is null and a.prometido_fonte = 'meio_dia'
         and (a.prometido_ate at time zone c_fuso)::date = v_hoje;
      v_texto := format('Retorno · meio-dia: %s promessa(s) até as %s. O cartão aberto já tem: *retorno*.', v_k,
                        public._retorno_hora(v_cfg.promessa_meio_dia));
      insert into public.retorno_cartoes (gatilho, dia, estado, aviso_id, hash, texto, criado_em, expira_em, dados)
      values ('meio_dia', v_hoje, 'lista', p_aviso, md5(v_texto), v_texto, v_agora, v_agora + v_cfg.cartao_validade, '{"so_aviso": true}')
      returning id into v_cartao;
      select d.phone into v_phone from public._comprovante_dono() d;
      perform public.aviso_registrar(jsonb_build_object('phone', v_phone, 'modo', public._retorno_modo_da_voz(), 'fonte', 'cliente',
        'chave', 'retorno:meio_dia:' || v_hoje, 'assunto', 'retorno:meio_dia', 'destino', 'deixar', 'texto', v_texto, 'agora', v_agora));
      return jsonb_build_object('acao', 'lista', 'cartao_id', v_cartao, 'texto', v_texto, 'phone', v_phone);
    else
      perform public._retorno_a01_na_fila(p_aviso, v_agora);
      return jsonb_build_object('acao', 'ja_vivo');
    end if;
  end if;

  select count(*) into v_total from public._orcamento_cartao_lista(v_agora, null);   -- F5 (P7): casos, aceites e passos (C-LISTA)
  if v_total = 0 then
    -- O acorde que esperava o cartão: sem nada a mostrar, o aviso vai pela fila e o minuto seguinte não repete.
    if p_gatilho = 'acorde' then
      perform public._retorno_a01_na_fila(p_aviso, v_agora);
    end if;
    return jsonb_build_object('acao', 'vazio', 'texto', 'Ninguém esperando agora.');
  end if;
  v_mais := greatest(0, v_total - v_cfg.cartao_max_itens);

  select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
  v_o := public.pergunta_ocupado(v_phone);
  v_ocupado := coalesce((v_o ->> 'ocupado')::boolean, false);
  if v_ocupado and p_gatilho = 'acorde' then
    perform public._retorno_a01_na_fila(p_aviso, v_agora);
    return jsonb_build_object('acao', 'ocupado');
  end if;

  v_expira := v_agora + v_cfg.cartao_validade;
  insert into public.retorno_cartoes (gatilho, dia, estado, aviso_id, hash, texto, mais, criado_em, expira_em, dados)
  values (p_gatilho, v_hoje, 'lista', p_aviso, '', '', v_mais, v_agora, v_expira,
          jsonb_build_object('rodape', case
            when not v_cfg.cartao_ligado then '*ver 1* · *resolvido 1* · *pessoal 1*'
            when v_ocupado then 'Tem um pedido aberto antes deste: responda a ele e mande *retorno* de novo.' end))
  returning id into v_cartao;

  for v_caso in select c.abertura_id, c.aceite_id, c.passo_id, c.tipo
                  from public._orcamento_cartao_lista(v_agora, v_cfg.cartao_max_itens) c order by c.ordem loop   -- F5 (P7)
    v_n := v_n + 1;
    -- F5 (P7): o caso da F2 tem o montador dele; o aceite, os dados da nota e o passo, os da F5 (o mesmo formato).
    v_item := (case v_caso.tipo
                 when 'aceite' then public._orcamento_item_aceite(v_caso.abertura_id, v_caso.aceite_id, v_n, v_agora)
                 when 'dados_nota' then public._orcamento_item_dados(v_caso.abertura_id, v_caso.aceite_id, v_n, v_agora)
                 when 'cadencia' then public._orcamento_item_montar_passo(v_caso.passo_id, v_n, v_agora)
                 else public._retorno_item_montar(v_caso.abertura_id, v_n, v_agora) end);
    insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, modelo_tipo, service_order_id, texto_mostrado,
                                             opcoes, fatos, hash, previa_id, acao_sim, passo_id, aceite_id)   -- F5 (P7)
    values (v_cartao, v_n, v_caso.abertura_id, v_item ->> 'tipo_item', v_item ->> 'modelo_tipo',
            (v_item ->> 'service_order_id')::uuid, v_item ->> 'texto_mostrado', v_item -> 'opcoes', v_item -> 'fatos',
            v_item ->> 'hash', (v_item ->> 'previa_id')::uuid, v_item ->> 'acao_sim',   -- F3 (P5)
            (v_item ->> 'passo_id')::uuid, (v_item ->> 'aceite_id')::uuid);   -- F5 (P7)
    v_linhas := v_linhas || jsonb_build_object(v_n::text, v_item -> 'linhas');
    v_hashes := v_hashes || (v_item ->> 'hash');
    -- F5 (P7): o item sem caso tem o rótulo do orçamento (o _retorno_rotulo de caso nulo dá "contato").
    v_rotulos := v_rotulos || format('%s = %s', v_n, coalesce(v_item ->> 'rotulo', public._retorno_rotulo(v_caso.abertura_id, v_agora)));
    v_nomes := v_nomes || coalesce(v_item ->> 'rotulo', public._retorno_rotulo(v_caso.abertura_id, v_agora));
  end loop;

  update public.retorno_cartoes c
     set hash = md5(v_hashes), dados = c.dados || jsonb_build_object('linhas', v_linhas)
   where c.id = v_cartao;

  if not v_cfg.cartao_ligado or v_ocupado then
    v_texto := public._retorno_cartao_texto(v_cartao, null);
    update public.retorno_cartoes c set texto = v_texto where c.id = v_cartao;
    if p_gatilho = 'meio_dia' then
      v_chave_aviso := 'retorno:meio_dia:' || v_hoje;
      perform public.aviso_registrar(jsonb_build_object('phone', v_phone, 'modo', public._retorno_modo_da_voz(), 'fonte', 'cliente',
        'chave', v_chave_aviso, 'assunto', 'retorno:meio_dia', 'destino', 'deixar', 'texto', split_part(v_texto, E'\n', 1), 'agora', v_agora));
    end if;
    return jsonb_build_object('acao', 'lista', 'cartao_id', v_cartao, 'texto', v_texto, 'phone', v_phone,
      'historico', jsonb_build_object('user', '(retorno)',
        'assistant', format('Mostrei a lista do retorno: %s caso(s). %s. O que os clientes escreveram fica fora desta conversa.',
                            v_total, array_to_string(v_rotulos, ', '))));
  end if;

  -- Cartão vivo: sessão, pendência, ponteiro por merge, registro da pergunta, par da conversa e auditoria.
  v_sessao := public._retorno_sessao_do_dono(v_dono, v_phone, v_agora);
  insert into public.ai_operator_pending_actions (session_id, requested_by_user_id, action_name, risk_level, risk_reason, title, summary,
                                                  payload, status, expires_at)
  values (v_sessao, v_dono, 'retorno_executar_cartao', 'high', 'manda mensagem ao cliente', 'Cartão do retorno',
          format('Cartão do retorno: %s casos (%s). Mande *retorno* para ver.', v_n, array_to_string(v_nomes, ', ')),
          jsonb_build_object('cartao_id', v_cartao), 'pending', v_expira)
  returning id into v_pend;

  update public.ai_operator_sessions s
     set metadata = coalesce(s.metadata, '{}'::jsonb)
                    || jsonb_build_object('pending_confirm_action_id', v_pend, 'pin_attempts', 0, 'pendencia_herdada', false),
         last_activity_at = v_agora
   where s.id = v_sessao;

  v_perg := public.pergunta_registrar_externa(jsonb_build_object('phone', v_phone, 'origem', 'acompanhar_conversa', 'tipo', 'confirmacao',
    'referencia_id', v_pend, 'titulo', 'Cartão do retorno'));

  insert into public.ai_operator_messages (session_id, role, content, source) values
    (v_sessao, 'user', format('🤖 Cartão do retorno (aviso automático): %s casos.', v_n), 'whatsapp'),
    (v_sessao, 'assistant', format('Cartão do retorno aberto (pendência %s). Casos: %s. O que os clientes escreveram fica fora desta conversa; para ler, use retorno_ler_caso.',
                                   v_pend, array_to_string(v_rotulos, ', ')), 'whatsapp');

  insert into public.ai_operator_audit (session_id, pending_action_id, actor_user_id, actor_kind, event_type, event_category, payload)
  values (v_sessao, v_pend, v_dono, 'system', 'retorno:cartao:proposto', 'channel',
          jsonb_build_object('cartao_id', v_cartao, 'itens', v_n, 'gatilho', p_gatilho));

  update public.retorno_cartoes c
     set estado = 'vivo', sessao_id = v_sessao, pendencia_id = v_pend, pergunta_id = (v_perg ->> 'id')::uuid
   where c.id = v_cartao;
  v_texto := public._retorno_cartao_texto(v_cartao, null);
  update public.retorno_cartoes c set texto = v_texto where c.id = v_cartao;

  if p_gatilho = 'meio_dia' then
    perform public.aviso_registrar(jsonb_build_object('phone', v_phone, 'modo', public._retorno_modo_da_voz(), 'fonte', 'cliente',
      'chave', 'retorno:meio_dia:' || v_hoje, 'assunto', 'retorno:meio_dia', 'destino', 'deixar', 'texto', split_part(v_texto, E'\n', 1), 'agora', v_agora));
  elsif p_gatilho = 'acorde' then
    update public.retorno_saidas s set dados = s.dados - 'aguarda_cartao', atualizada_em = now()
     where s.tipo = 'acorde' and s.dados ->> 'aviso_id' = p_aviso::text;
  end if;

  return jsonb_build_object('acao', 'cartao', 'cartao_id', v_cartao, 'phone', v_phone, 'texto', v_texto, 'pergunta_id', v_perg ->> 'id');
end;
$$;
revoke all on function public.retorno_cartao_abrir(text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.retorno_cartao_abrir(text, timestamptz, uuid) to service_role;

create or replace function public._retorno_cartao_texto(p_cartao uuid, p_cabeca text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_c public.retorno_cartoes;
  v_vivos integer;
  v_cabeca text;
  v_corpo text;
  v_primeiro smallint;
  v_mandam smallint[];
  v_faz text;
  v_rodape text;
  v_max boolean;
  -- F3 (P5)
  v_orc smallint[];
  v_orc_acao text;
  v_tem_proposta boolean;
  v_final text;
  v_lim integer;
  v_f5_mandam smallint[];   -- F5 (P7)
  v_f5_espera text;         -- F5 (P7)
begin
  select * into v_c from public.retorno_cartoes c where c.id = p_cartao;
  select count(*), min(i.n) into v_vivos, v_primeiro
    from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo';

  v_cabeca := coalesce(p_cabeca, case when v_c.gatilho = 'meio_dia' then format('Retorno · meio-dia · %s esperando', v_vivos + v_c.mais)
                                      else format('Retorno · %s esperando', v_vivos + v_c.mais) end);

  select string_agg(l.linha, E'\n' order by i.n, l.ord)
    into v_corpo
    from public.retorno_cartao_itens i
    cross join lateral jsonb_array_elements_text(coalesce(v_c.dados -> 'linhas' -> i.n::text, '[]'::jsonb))
         with ordinality as l(linha, ord)
   where i.cartao_id = p_cartao and i.estado = 'vivo';

  if v_c.estado = 'vivo' then
    select array_agg(i.n order by i.n) into v_mandam
      from public.retorno_cartao_itens i
     where i.cartao_id = p_cartao and i.estado = 'vivo' and (i.modelo_tipo is not null or i.texto_ditado is not null);
    -- F3 (P5): item com acao_sim, sem ditado e sem provisório entra no que o *sim <PIN>* faz. Item com provisório e item com texto_ditado, não.
    select array_agg(i.n order by i.n), min(i.acao_sim)
      into v_orc, v_orc_acao
      from public.retorno_cartao_itens i
      left join public.retorno_previa p on p.id = i.previa_id
     where i.cartao_id = p_cartao and i.estado = 'vivo' and i.acao_sim is not null and i.texto_ditado is null
       and (i.acao_sim = 'pdf' or coalesce(p.provisorios_n, 0) = 0);
    if v_orc is not null then
      select array_agg(x order by x) into v_mandam
        from (select unnest(v_mandam) as x union select unnest(v_orc)) t;
    end if;
    -- F5 (P7): o item de aceite ou de dados da nota com letra escolhida entra no que o *sim <PIN>* faz (o de cadência já entra
    -- pelo modelo_tipo).
    select array_agg(i.n order by i.n) into v_f5_mandam
      from public.retorno_cartao_itens i
     where i.cartao_id = p_cartao and i.estado = 'vivo' and i.tipo_item in ('aceite', 'dados_nota')
       and i.escolha is not null and i.texto_ditado is null;
    if v_f5_mandam is not null then
      select array_agg(x order by x) into v_mandam
        from (select unnest(v_mandam) as x union select unnest(v_f5_mandam)) t;
    end if;
    select exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo' and i.previa_id is not null)
      into v_tem_proposta;
    if cardinality(v_mandam) > 0 then
      v_faz := case when cardinality(v_mandam) = 1 then format('o %s', v_mandam[1])
                    when cardinality(v_mandam) = 2 then format('o %s e o %s', v_mandam[1], v_mandam[2])
                    else 'os 3' end;
      -- F3 (P5): um item só de orçamento diz o que o *sim <PIN>* faz.
      if cardinality(v_mandam) = 1 and v_orc is not null then
        v_faz := v_faz || case when v_orc_acao = 'pdf' then ' (manda o PDF)' else ' (cria o orçamento e manda o PDF)' end;
      end if;
      -- F5 (P7): um item só, de aceite ou de dados, diz o que a letra faz.
      if cardinality(v_mandam) = 1 and v_f5_mandam is not null then
        v_faz := v_faz || coalesce((select (case i.escolha
                                              when 'A' then (case when i.tipo_item = 'dados_nota' then ' (grava na ficha)'
                                                                  else format(' (aprova o %s e fica aguardando o sinal)', so.service_order_number) end)
                                              when 'B' then format(' (converte o %s em OS sem sinal)', so.service_order_number)
                                              when 'C' then format(' (aprova o %s, aguarda o sinal e pede os dados)', so.service_order_number)
                                              when 'D' then format(' (converte o %s em OS sem sinal e pede os dados)', so.service_order_number)
                                            end)
                                      from public.retorno_cartao_itens i
                                      left join public.service_orders so on so.id = i.service_order_id
                                     where i.cartao_id = p_cartao and i.n = v_mandam[1] and i.estado = 'vivo'), '');
      end if;
      v_rodape := format('*sim <PIN>* faz %s · *só %s* · *ver %s* · *não* · ou dite por áudio', v_faz, v_mandam[1], v_primeiro);
    elsif v_primeiro is null then
      v_rodape := 'Nada mais neste cartão. *retorno* abre de novo.';
    else
      v_rodape := format('*ver %1$s* · *dita %1$s …* · *não* · ou dite por áudio', v_primeiro);
    end if;
    -- F5 (P7): sem nada para o *sim* fazer e com o 1º item sem conversa (aceite ou passo sem caso), o rodapé não ensina *dita*.
    if coalesce(cardinality(v_mandam), 0) = 0 and v_primeiro is not null
       and exists (select 1 from public.retorno_cartao_itens i
                    where i.cartao_id = p_cartao and i.estado = 'vivo' and i.n = v_primeiro and i.abertura_id is null) then
      v_rodape := format('*ver %1$s* · *não* · ou responda pelo assistente', v_primeiro);
    end if;
    -- F5 (P7): o item de aceite ou de dados da nota que ainda espera a letra diz quais são.
    select string_agg(format('O %s espera a sua letra (%s) antes do *sim*.', x.n, x.letras), ' ' order by x.n)
      into v_f5_espera
      from (select i.n, (select string_agg(format('*%s %s*', i.n, o ->> 'letra'), ' · ' order by o ->> 'letra')
                           from jsonb_array_elements(i.opcoes) o) as letras
              from public.retorno_cartao_itens i
             where i.cartao_id = p_cartao and i.estado = 'vivo' and i.tipo_item in ('aceite', 'dados_nota')
               and i.escolha is null and i.texto_ditado is null and jsonb_array_length(i.opcoes) > 0) x;
    if v_f5_espera is not null then
      v_rodape := v_rodape || E'\n' || v_f5_espera;
    end if;
    -- F3 (P5): com proposta, o áudio dita o que mudar nela.
    if v_tem_proposta then
      v_rodape := replace(v_rodape, 'ou dite por áudio', 'ou dite o que mudar');
    end if;
    begin
      v_max := public.ai_claude_max_disponivel();
      if v_max is false then
        v_rodape := v_rodape || E'\n' || '(Seu assistente está fora: responda com as letras ou pelo celular.)';
      end if;
    exception when others then
      null;   -- erro ao ler: a linha não aparece
    end;
  else
    v_rodape := v_c.dados ->> 'rodape';
  end if;

  v_final := concat_ws(E'\n', v_cabeca, v_corpo,
                       case when v_c.mais > 0 then format('e mais %s: *retorno*', v_c.mais) end,
                       v_rodape);
  -- F3 (P5): retorno_cartoes.texto tem CHECK de 3.500 (estourar derruba o *retorno* inteiro). As linhas C30 (as que começam com "   · ") são as primeiras a sair.
  if char_length(v_final) > 3500 then
    foreach v_lim in array array[8, 6, 4, 2, 0] loop
      select string_agg(case when not x.c30 or x.k30 <= v_lim then x.linha
                             else format('   · e mais %s: *ver %s*', x.total30 - v_lim, x.n) end,
                        E'\n' order by x.n, x.ord)
        into v_corpo
        from (select i.n, l.ord, l.linha, l.linha like '   · %' as c30,
                     count(*) filter (where l.linha like '   · %') over (partition by i.n order by l.ord) as k30,
                     count(*) filter (where l.linha like '   · %') over (partition by i.n) as total30
                from public.retorno_cartao_itens i
                cross join lateral jsonb_array_elements_text(coalesce(v_c.dados -> 'linhas' -> i.n::text, '[]'::jsonb))
                     with ordinality as l(linha, ord)
               where i.cartao_id = p_cartao and i.estado = 'vivo') x
       where not x.c30 or x.k30 <= v_lim + 1;
      v_final := concat_ws(E'\n', v_cabeca, v_corpo,
                           case when v_c.mais > 0 then format('e mais %s: *retorno*', v_c.mais) end,
                           v_rodape);
      exit when char_length(v_final) <= 3500;
    end loop;
  end if;
  return v_final;
end;
$$;
revoke all on function public._retorno_cartao_texto(uuid, text) from public, anon, authenticated;

create or replace function public._retorno_item_conferir(p_item uuid, p_agora timestamptz, p_executar boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_i public.retorno_cartao_itens;
  v_c public.retorno_cartoes;
  v_ab public.retorno_aberturas;
  v_resp timestamptz;
  v_quem jsonb;
  v_atual jsonb;   -- F3 (P5)
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'caso_fechado', 'texto', 'o item já não existe; não mandei');
  end if;
  select * into v_c from public.retorno_cartoes c where c.id = v_i.cartao_id;
  select * into v_ab from public.retorno_aberturas a where a.id = v_i.abertura_id;

  -- F5 (P7): os itens do orçamento têm a conferência deles (o estado do caso não conta; a cadência confere o passo e a parada).
  if v_i.tipo_item in ('aceite', 'dados_nota', 'cadencia') then
    return public._orcamento_item_conferir(v_i.id, p_agora, p_executar);
  end if;

  if v_ab.estado = 'fechada' then
    return jsonb_build_object('ok', false, 'motivo', 'caso_fechado', 'texto', format('o %s já estava resolvido; não mandei', v_i.n));
  end if;

  if v_c.enviado_em is not null then
    v_resp := public._retorno_resposta_depois(v_ab.id, v_c.enviado_em, p_agora);
  end if;
  if v_resp is not null then
    return jsonb_build_object('ok', false, 'motivo', 'respondida_pelo_dono',
      'texto', format('o %s caiu: você já respondeu às %s; não mandei', v_i.n, to_char(v_resp at time zone c_fuso, 'HH24:MI')));
  end if;

  if p_executar and v_i.modelo_tipo is not null
     and (public._retorno_item_montar(v_ab.id, v_i.n, p_agora) ->> 'hash') is distinct from v_i.hash then
    return jsonb_build_object('ok', false, 'motivo', 'fato_mudou',
      'texto', format('o %s mudou desde o cartão: mande *retorno* para ver de novo; não mandei', v_i.n));
  end if;

  -- F3 (P5): o *sim <PIN>* vale sobre o que o dono leu. Compara também a proposta e o orçamento, que o hash sozinho não pega (outro previa_id com as mesmas linhas).
  -- Item com texto_ditado segue a regra da F2: o executor manda só o texto ditado, e a proposta não entra.
  -- Com a flag da ação desligada, quem responde é a 1ª regra do bloco de orçamento em retorno_cartao_executar: item fora, "foi desligado". Sem isto, o item
  -- remontado com as flags desligadas não bate, e o dono leria que o caso mudou.
  if p_executar and v_i.acao_sim is not null and v_i.modelo_tipo is null and v_i.texto_ditado is null
     and public._retorno_previa_liberada(v_i.acao_sim, (select p.origem from public.retorno_previa p where p.id = v_i.previa_id)) then
    v_atual := public._retorno_item_montar(v_ab.id, v_i.n, p_agora);
    if (v_atual ->> 'hash') is distinct from v_i.hash
       or (v_atual ->> 'previa_id')::uuid is distinct from v_i.previa_id
       or (v_atual ->> 'service_order_id')::uuid is distinct from v_i.service_order_id
       or (v_i.acao_sim = 'orcar' and not exists (select 1 from public.retorno_previa p where p.id = v_i.previa_id and p.estado = 'proposta')) then
      return jsonb_build_object('ok', false, 'motivo', 'fato_mudou',
        'texto', format('o %s mudou desde o cartão: mande *retorno* para ver de novo; não mandei', v_i.n));
    end if;
  end if;

  if v_ab.papel = 'cliente' then
    v_quem := public.quem_escreve(v_ab.phone_normalized);
    if (v_quem ->> 'cliente_id')::uuid is distinct from v_ab.client_id then
      return jsonb_build_object('ok', false, 'motivo', 'telefone_mudou', 'texto', format('o %s mudou de número; não mandei', v_i.n));
    end if;
  end if;

  if public.canal_bloqueado(v_ab.phone_normalized) is not null
     or v_ab.nivel = 'nada'
     or exists (select 1 from public.whatsapp_leads l
                 where l.lead_tipo = 'pessoal' and public._agenda_chave_telefone(l.phone_normalized) = v_ab.chave) then
    return jsonb_build_object('ok', false, 'motivo', 'canal_bloqueado',
      'texto', format('o %s pediu para não receber mensagem automática: responda pelo celular se for preciso; não mandei', v_i.n));
  end if;

  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public._retorno_item_conferir(uuid, timestamptz, boolean) from public, anon, authenticated;

create or replace function public._retorno_decidir_letra(p_item public.retorno_cartao_itens, p_comando jsonb, p_dono uuid, p_agora timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_hoje date := (p_agora at time zone c_fuso)::date;
  v_letra text := upper(coalesce(p_comando ->> 'letra', ''));
  v_resto text := nullif(btrim(p_comando ->> 'resto'), '');
  v_op jsonb;
  v_rotulo text := public._retorno_rotulo(p_item.abertura_id, p_agora);
  v_r jsonb;
  v_item jsonb;
  v_m jsonb;
  v_nivel text;
  v_texto text;
  v_dia date;
  v_prov uuid;
  v_ves uuid;
  v_cli uuid;   -- F3 (P6)
begin
  -- F5 (P7): a letra do item de aceite e de dados da nota é do executor da F5 (não tem caso nem ação da F2/F3).
  if p_item.tipo_item in ('aceite', 'dados_nota') then
    return public._orcamento_decidir_letra(p_item, p_comando, p_dono, p_agora);
  end if;
  select o into v_op from jsonb_array_elements(p_item.opcoes) o where o ->> 'letra' = v_letra limit 1;
  if v_op is null then
    return jsonb_build_object('ok', true, 'texto', format('O caso %s não tem a opção %s, e nada foi feito.', p_item.n, v_letra));
  end if;

  case v_op ->> 'acao'
    when 'chegou', 'previsao' then
      if v_op ->> 'acao' = 'previsao' and v_resto is null then
        return jsonb_build_object('ok', true, 'texto', format('Diga a previsão: *%s C dia 14*.', p_item.n));
      end if;
      if exists (select 1 from public.agenda_rascunho r where r.autor = p_dono and r.estado = 'aberto' and r.expira_em > p_agora) then
        return jsonb_build_object('ok', true, 'texto', 'Tem um rascunho aberto: mande *grava* ou *descarta* antes.');
      end if;
      if v_op ->> 'acao' = 'chegou' then
        v_r := public._retorno_material(p_dono, v_op ->> 'os', 'na_mao', null, format('cartão do retorno: %s B', p_item.n), v_hoje);
      else
        v_r := public._retorno_material(p_dono, v_op ->> 'os', 'a_caminho', v_resto,
                                        format('cartão do retorno: %s C %s', p_item.n, v_resto), v_hoje);
      end if;
      if not (v_r ->> 'ok')::boolean then
        return jsonb_build_object('ok', true, 'texto', v_r ->> 'texto');
      end if;

      if v_op ->> 'acao' = 'previsao' then
        select max(m.previsao_ate) into v_dia from public.os_material m
         where m.service_order_id = p_item.service_order_id and m.critico and m.situacao = 'a_caminho';
        perform public._retorno_item_remontar(p_item.id, p_agora);
        return jsonb_build_object('ok', true,
          'texto', format('Anotei: previsão %s. Só você vê: ao cliente não vai data.', coalesce(to_char(v_dia, 'DD/MM'), 'anotada')));
      end if;

      v_item := public._retorno_item_remontar(p_item.id, p_agora);
      v_m := public._retorno_modelo_do_caso(p_item.abertura_id, p_agora);
      select t.nivel into v_nivel from public.retorno_modelo_tipos t where t.tipo = 'modelo_peca_chegou';
      if v_m ->> 'modelo' = 'modelo_peca_chegou' and v_nivel = 'cartao' then
        return jsonb_build_object('ok', true, 'precisa_pin', true,
          'texto', format('Anotei: chegou hoje. Mando a %s: ''%s''? *sim <PIN>*', v_rotulo, v_item ->> 'texto_mostrado'));
      elsif v_m ->> 'modelo' = 'modelo_peca_chegou' and v_nivel = 'sozinho' then
        perform public._retorno_agendar_modelo(p_item.abertura_id, v_m, p_agora);
        return jsonb_build_object('ok', true, 'texto', format('Anotei: chegou hoje. Vai sair a %s.', v_rotulo));
      end if;
      return jsonb_build_object('ok', true, 'texto', 'Anotei: chegou hoje. A agenda avisa o cliente quando marcar o dia.');

    when 'responder' then
      -- F3 (P6): a letra L com o ditado desligado não vale: M07 não sai sem as letras ligadas.
      if v_op ->> 'modelo' = 'modelo_ver_no_local' and not coalesce((public._retorno_cfg()).previa_ditado_ligado, false) then
        return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', 'O orçamento pelo cartão está desligado: nada mudou.');
      end if;
      v_texto := public._retorno_texto_do_modelo(p_item.abertura_id,
        jsonb_build_object('modelo', v_op ->> 'modelo', 'os_id', v_op ->> 'os_id'), null, p_agora);
      -- F3 (P6): acao_sim = null, com previa_id intacto. Sem isso, *L* + *sim <PIN>* criaria o orçamento e mandaria o PDF.
      update public.retorno_cartao_itens i
         set texto_mostrado = v_texto, modelo_tipo = v_op ->> 'modelo', escolha = v_letra, selecionado = true, acao_sim = null
       where i.id = p_item.id;
      update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = p_item.cartao_id;
      return jsonb_build_object('ok', true, 'precisa_pin', true,
        'texto', format('Vou mandar a %s: ''%s''. *sim <PIN>* manda.', v_rotulo, v_texto));

    when 'parecido' then
      -- F3 (P6): *B* troca pelo outro parecido. p_fonte só vale com previa_modo = 'ligado' (retorno_previa_montar também barra).
      -- pin_nao_vale (revisão da F3): o PIN mandado junto da letra não vale. O dono lê as linhas novas e manda *sim <PIN>* sozinho, inclusive quando nada mudou.
      if (public._retorno_cfg()).previa_modo is distinct from 'ligado' then
        return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', 'O orçamento pelo cartão está desligado: nada mudou.');
      end if;
      v_r := public.retorno_previa_montar(p_item.abertura_id, p_agora, (v_op ->> 'os_id')::uuid);
      if v_r ->> 'acao' = 'nada' then
        return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', 'Não consegui usar esse orçamento: nada mudou.');
      end if;
      v_item := public._retorno_item_remontar(p_item.id, p_agora);
      return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', (select string_agg(l, E'\n') from jsonb_array_elements_text(v_item -> 'linhas') l));

    when 'unidade' then
      -- F3 (P6): a escolha do dono vale mais que a busca por nome; a proposta fica travada e o hash é recalculado (a rodada a mantém).
      v_cli := (public._retorno_cadastro_do_caso(p_item.abertura_id) ->> 'client_id')::uuid;
      v_ves := (v_op ->> 'vessel_id')::uuid;
      if v_cli is null or not exists (select 1 from public.vessels v where v.id = v_ves and v.active and v.client_id = v_cli) then
        return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', format('A unidade da opção %s já não vale para este cliente, e nada foi feito. Mande *retorno*.', v_letra));
      end if;
      update public.retorno_aberturas a set unidade_escolhida_id = v_ves, atualizada_em = now() where a.id = p_item.abertura_id;
      update public.retorno_previa p
         set vessel_id = v_ves,
             hash = public._retorno_previa_hash(v_ves, p.titulo, public._retorno_previa_linhas_json(p.id)),
             dados = p.dados || '{"travada": true}'::jsonb,
             atualizada_em = p_agora
       where p.abertura_id = p_item.abertura_id and p.estado in ('proposta', 'sombra');
      v_item := public._retorno_item_remontar(p_item.id, p_agora);
      return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', (select string_agg(l, E'\n') from jsonb_array_elements_text(v_item -> 'linhas') l));

    when 'cliente' then
      -- Vale só para este caso: não vincula o número nem regrava mensagem.
      update public.retorno_aberturas a
         set client_id = (v_op ->> 'client_id')::uuid, papel = 'cliente', atualizada_em = now()
       where a.id = p_item.abertura_id;
      v_item := public._retorno_item_remontar(p_item.id, p_agora);
      -- Revisão da F3: definido o cliente, o item pode nascer com um rascunho dele a mandar, que o dono ainda não leu.
      return jsonb_build_object('ok', true, 'pin_nao_vale', (v_item ->> 'acao_sim') is not null, 'texto', (select string_agg(l, E'\n') from jsonb_array_elements_text(v_item -> 'linhas') l));

    when 'desfaz_cadastro' then
      v_prov := (v_op ->> 'client_id')::uuid;
      select (a.new_value ->> 'vessel_id')::uuid into v_ves
        from public.audit_log a
       where a.table_name = 'clients' and a.record_id = v_prov and a.new_value ->> 'caso' = p_item.abertura_id::text
       limit 1;
      update public.clients c set active = false where c.id = v_prov;
      update public.vessels v set active = false where v.id = v_ves;
      insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
      values ('clients', v_prov, 'update', 'dono', jsonb_build_object('active', true), jsonb_build_object('active', false),
              'Cadastro provisório desfeito pelo dono no cartão do retorno');
      -- F3 (P6): sem cadastro não há proposta: as vivas caem, e _retorno_cadastro_do_caso já devolve nulo (o *sim <PIN>* não cria nada nele).
      update public.retorno_previa p set estado = 'descartada', atualizada_em = p_agora
       where p.abertura_id = p_item.abertura_id and p.estado in ('proposta', 'sombra');
      if (public._retorno_cfg()).previa_ditado_ligado or (public._retorno_cfg()).previa_modo = 'ligado' then
        perform public._retorno_item_remontar(p_item.id, p_agora);
      end if;
      return jsonb_build_object('ok', true, 'texto', 'Cadastro provisório desfeito. Nada foi apagado.');

    else
      return jsonb_build_object('ok', true, 'texto', format('O caso %s não tem a opção %s, e nada foi feito.', p_item.n, v_letra));
  end case;
end;
$$;
revoke all on function public._retorno_decidir_letra(public.retorno_cartao_itens, jsonb, uuid, timestamptz) from public, anon, authenticated;

create or replace function public.retorno_decidir_dito(p_comando jsonb, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cmd text := p_comando ->> 'comando';
  v_n integer := (p_comando ->> 'n')::integer;
  v_ns integer[] := case when jsonb_typeof(p_comando -> 'ns') = 'array'
                         then array(select (x)::integer from jsonb_array_elements_text(p_comando -> 'ns') x) end;
  v_vivo jsonb;
  v_cartao uuid;
  v_k integer;
  v_item public.retorno_cartao_itens;
  v_r jsonb;
  v_sel integer[];
  v_texto text;
  v_ditado text;
  v_aviso text;
  v_palavra text;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'motivo', 'nao_e_o_dono');
  end if;
  v_vivo := public.retorno_cartao_vivo(v_agora);
  if v_vivo is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;
  if v_vivo ->> 'estado' = 'lista' then
    return jsonb_build_object('ok', true, 'texto', 'Esta lista é só para consulta. Mande *retorno* quando o pedido aberto terminar.');
  end if;
  v_cartao := (v_vivo ->> 'id')::uuid;

  select count(*) into v_k from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo';
  if (v_n is not null and not exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = v_n and i.estado = 'vivo'))
     or (v_ns is not null and exists (select 1 from unnest(v_ns) x
                                       where not exists (select 1 from public.retorno_cartao_itens i
                                                          where i.cartao_id = v_cartao and i.n = x and i.estado = 'vivo'))) then
    return jsonb_build_object('ok', true, 'texto', format('O cartão tem %s casos.', v_k));
  end if;
  if v_n is not null then
    select * into v_item from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = v_n;
  end if;

  case v_cmd
    when 'escolher' then
      v_palavra := 'letra';
      v_r := public._retorno_decidir_letra(v_item, p_comando, p_autor, v_agora);
      perform public._retorno_toque(v_palavra, v_cartao, v_item.abertura_id, v_agora);
      return v_r || jsonb_build_object('historico', jsonb_build_object('user', format('(escolheu %s no caso %s)', upper(p_comando ->> 'letra'), v_n),
                                                                       'assistant', format('(anotei a escolha do caso %s)', v_n)));

    when 'so', 'sem' then
      update public.retorno_cartao_itens i
         set selecionado = case when v_cmd = 'so' then i.n = any (v_ns) else not (i.n = any (v_ns)) end
       where i.cartao_id = v_cartao and i.estado = 'vivo';
      select array_agg(i.n::integer order by i.n) into v_sel
        from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo' and i.selecionado;
      -- F5 (P7): *só* e *sem* refazem a seleção do cartão inteiro; o "não era" fica só com o *não N* explícito.
      update public.retorno_cartao_itens i set tirado_em = null
       where i.cartao_id = v_cartao and i.estado = 'vivo' and i.tirado_em is not null;
      perform public._retorno_toque(v_cmd, v_cartao, null, v_agora);
      if v_sel is null then
        return jsonb_build_object('ok', true, 'texto', 'Nada ficou selecionado. *retorno* volta ao cartão inteiro.',
          'historico', jsonb_build_object('user', format('(%s)', v_cmd), 'assistant', '(nada selecionado no cartão)'));
      end if;
      v_texto := format('Fica %s. *sim <PIN>* manda. *retorno* volta ao cartão inteiro.', public._retorno_lista_de_casos(v_sel));
      return jsonb_build_object('ok', true, 'precisa_pin', true, 'texto', v_texto,
        'historico', jsonb_build_object('user', format('(%s %s)', v_cmd, array_to_string(v_ns, ' ')), 'assistant', v_texto));

    when 'tirar' then
      update public.retorno_cartao_itens i set selecionado = false where i.cartao_id = v_cartao and i.estado = 'vivo' and i.n = any (v_ns);
      -- F5 (P7): o *não N* explícito num item do orçamento fica marcado; só ele dá desfecho (não era, dados nada, passo tirado).
      update public.retorno_cartao_itens i set tirado_em = v_agora
       where i.cartao_id = v_cartao and i.estado = 'vivo' and i.n = any (v_ns) and i.tipo_item in ('aceite', 'dados_nota', 'cadencia');
      perform public._retorno_toque('tirar', v_cartao, null, v_agora);
      if not exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo' and i.selecionado) then
        perform public._orcamento_cartao_tirados(v_cartao, v_agora);   -- F5 (P7): nada ficou selecionado; os itens do orçamento tirados têm desfecho
        perform public._retorno_cartao_recusar(v_cartao, v_agora);
        return jsonb_build_object('ok', true, 'texto', 'Cartão fechado: nada foi mandado.',
          'historico', jsonb_build_object('user', '(tirou os casos do cartão)', 'assistant', 'Cartão fechado: nada foi mandado.'));
      end if;
      v_texto := case when cardinality(v_ns) = 1 then format('Tirei o %s. O relógio dele continua.', v_ns[1])
                      else format('Tirei o %s. O relógio deles continua.', array_to_string(v_ns, ' e o ')) end;
      -- F5 (P7): o item do orçamento não tem relógio; a frase diz o que o *sim <PIN>* fará com ele (os da F2 seguem com a frase deles).
      if exists (select 1 from public.retorno_cartao_itens i
                  where i.cartao_id = v_cartao and i.estado = 'vivo' and i.n = any (v_ns) and i.tirado_em is not null) then
        select string_agg((case i.tipo_item
                             when 'aceite' then (case when exists (select 1 from public.orcamento_aceites a
                                                                    where a.id = i.aceite_id and a.estado in ('com_sinal', 'sem_sinal'))
                                                      then format('Tirei o %s: o aviso sai da lista.', i.n)
                                                      else format('Tirei o %s: com o *sim <PIN>*, anoto que não era aprovação.', i.n) end)
                             when 'dados_nota' then format('Tirei o %s: com o *sim <PIN>*, não gravo os dados.', i.n)
                             when 'cadencia' then format('Tirei o %s: com o *sim <PIN>*, essa mensagem do orçamento não sai.', i.n)
                             else format('Tirei o %s. O relógio dele continua.', i.n) end), ' ' order by i.n)
          into v_texto
          from public.retorno_cartao_itens i
         where i.cartao_id = v_cartao and i.estado = 'vivo' and i.n = any (v_ns);
      end if;
      return jsonb_build_object('ok', true, 'texto', v_texto,
        'historico', jsonb_build_object('user', format('(não %s)', array_to_string(v_ns, ' ')), 'assistant', v_texto));

    when 'ditar' then
      v_ditado := btrim(coalesce(p_comando ->> 'texto', ''));
      if v_ditado = '' then
        return jsonb_build_object('ok', true, 'texto', format('Diga o texto: *dita %s pode buscar amanhã*.', v_n));
      end if;
      -- F5 (P7): item sem conversa aberta (cadência, aceite ou dados da nota sem caso) não tem para quem ditar. No item de aceite
      -- ou de dados com caso, o ditado vale (rr-f2-4) e tira a letra: com o ditado, o orçamento fica com o dono.
      if v_item.abertura_id is null then
        return jsonb_build_object('ok', true, 'texto', 'Este item não tem conversa aberta: responda pelo assistente.',
          'historico', jsonb_build_object('user', format('(ditou o item %s)', v_n), 'assistant', '(recusei o ditado: item sem conversa)'));
      end if;
      if v_item.tipo_item in ('aceite', 'dados_nota') then
        update public.retorno_cartao_itens i set escolha = null where i.id = v_item.id;
      end if;
      -- F3 (P6, 7.3): com proposta viva, *dita* com cara de ajuste é ajuste da proposta, e *dita* mandaria o texto ao cliente.
      if v_item.previa_id is not null
         and exists (select 1 from public.retorno_previa p where p.id = v_item.previa_id and p.estado = 'proposta')
         and v_ditado ~* '^\s*(troca|tira|muda|poe|põe|coloca|aumenta|diminui|acrescenta|fica)\y' then
        return jsonb_build_object('ok', true,
          'texto', format('Isso parece ajuste da proposta, e *dita* manda o texto ao cliente. Diga sem o *dita*: ou mande *dita %s* com o texto completo ao cliente.', v_n),
          'historico', jsonb_build_object('user', format('(ditou o caso %s)', v_n), 'assistant', '(recusei o ditado: parecia ajuste da proposta)'));
      end if;
      update public.retorno_cartao_itens i
         set texto_ditado = v_ditado, ditado_via = 'dita', selecionado = true
       where i.id = v_item.id;
      update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = v_cartao;
      perform public._retorno_toque('dita', v_cartao, v_item.abertura_id, v_agora);
      v_aviso := case when v_ditado ~* '(R\$|\yreais\y|[0-9]+[[:space:]]*mil\y)' then ' (tem valor no texto)' else '' end;
      return jsonb_build_object('ok', true, 'precisa_pin', true,
        'texto', format('Vou mandar a %s, exatamente: ''%s''.%s', public._retorno_rotulo(v_item.abertura_id, v_agora), v_ditado, v_aviso)
                 || E'\n' || format('*sim <PIN>* manda o que está no cartão · *dita %1$s …* troca · *não %1$s* tira.', v_n),
        'historico', jsonb_build_object('user', format('(ditou a resposta do caso %s)', v_n),
                                        'assistant', format('(anotei o ditado do caso %s)', v_n)));

    else
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end case;
end;
$$;
revoke all on function public.retorno_decidir_dito(jsonb, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_decidir_dito(jsonb, uuid, timestamptz) to service_role;

create or replace function public.retorno_cartao_executar(p_cartao uuid, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_c public.retorno_cartoes;
  v_i public.retorno_cartao_itens;
  v_ab public.retorno_aberturas;
  v_conf jsonb;
  v_frases text[] := '{}';
  v_ditados jsonb := '[]'::jsonb;
  v_rotulos text[] := '{}';
  v_n integer := 0;
  v_saida uuid;
  v_op jsonb;
  v_aviso text;
  -- F3 (P6)
  v_orcamentos jsonb := '[]'::jsonb;
  v_pv public.retorno_previa;
  v_nomes text;
  v_aceites jsonb := '[]'::jsonb;   -- F5 (P7)
  v_f5 jsonb;                       -- F5 (P7)
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'aviso', 'Só o dono executa o cartão.');
  end if;
  select * into v_c from public.retorno_cartoes c where c.id = p_cartao for update;
  if not found or v_c.estado <> 'vivo' then
    return jsonb_build_object('ok', false, 'aviso', 'Esse cartão já foi decidido.');
  end if;

  -- F5 (P7): os itens do orçamento tirados (*não N*) têm desfecho antes de irem a 'fora': aceite nao_era, dados nada, passo pulado/tirado.
  perform public._orcamento_cartao_tirados(p_cartao, v_agora);
  update public.retorno_cartao_itens i set estado = 'fora' where i.cartao_id = p_cartao and i.estado = 'vivo' and not i.selecionado;

  for v_i in select i.* from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo' order by i.n loop
    -- F5 (P7): os itens do orçamento têm executor próprio, que confere (pelo _retorno_item_conferir) e decide. Vem antes desta
    -- conferência, do ramo do orçamento da F3 e do ramo de modelo_tipo: o item 'cadencia' tem modelo_tipo e não tem caso, e o
    -- ramo de modelo inseriria a saída com v_ab.chave nula (NOT NULL).
    if v_i.tipo_item in ('aceite', 'dados_nota', 'cadencia') then
      v_f5 := public._orcamento_item_executar(v_i.id, p_autor, v_agora);
      if v_f5 ->> 'frase' is not null then
        v_frases := v_frases || (v_f5 ->> 'frase');
      end if;
      v_aceites := v_aceites || coalesce(v_f5 -> 'aceites', '[]'::jsonb);
      v_ditados := v_ditados || coalesce(v_f5 -> 'ditados', '[]'::jsonb);
      if coalesce((v_f5 ->> 'vai_sair')::boolean, false) then
        v_n := v_n + 1;
        v_rotulos := v_rotulos || (v_f5 ->> 'rotulo');
      end if;
      continue;
    end if;
    v_conf := public._retorno_item_conferir(v_i.id, v_agora, true);
    if not (v_conf ->> 'ok')::boolean then
      update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = v_conf ->> 'motivo', decidido_em = v_agora where i.id = v_i.id;
      v_frases := v_frases || (v_conf ->> 'texto');
      continue;
    end if;
    select * into v_ab from public.retorno_aberturas a where a.id = v_i.abertura_id;

    -- F3 (P6): o item de orçamento. O SQL só decide; quem cria e manda é a ferramenta, e a frase de cada um sai dela (não soma em "Vai sair").
    if v_i.acao_sim is not null and v_i.texto_ditado is null and v_i.modelo_tipo is null then
      select p.* into v_pv from public.retorno_previa p where p.id = v_i.previa_id;
      if not public._retorno_previa_liberada(v_i.acao_sim, v_pv.origem) then
        update public.retorno_cartao_itens i set estado = 'fora' where i.id = v_i.id;
        v_frases := v_frases || format('o %s não saiu, porque o orçamento pelo cartão foi desligado; não criei nada', v_i.n);
        continue;
      end if;
      if v_cfg.modo <> 'ligado' then
        update public.retorno_cartao_itens i set estado = 'fora' where i.id = v_i.id;
        v_frases := v_frases || 'O retorno está em teste: não mandei.'::text;
        continue;
      end if;
      if v_cfg.segura_tudo_ate is not null and v_cfg.segura_tudo_ate > v_agora then
        update public.retorno_cartao_itens i set estado = 'fora' where i.id = v_i.id;
        v_frases := v_frases || '*segura tudo* está ligado: não mandei.'::text;
        continue;
      end if;
      if v_i.acao_sim = 'orcar' and v_pv.provisorios_n > 0 then
        select string_agg(left(l.nome, 40), ', ' order by l.ordem) into v_nomes
          from public.retorno_previa_linhas l where l.previa_id = v_pv.id and l.estado = 'provisorio';
        update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = 'item_provisorio', decidido_em = v_agora where i.id = v_i.id;
        v_frases := v_frases || format('o %s tem item a completar (%s): não criei nada. Mande *retorno* e dite o que falta', v_i.n, v_nomes);
        continue;
      end if;
      if public._retorno_fora_do_horario_de_envio(v_agora) then
        update public.retorno_cartao_itens i set estado = 'fora' where i.id = v_i.id;
        v_frases := v_frases || format('o %s: fora do horário de envio; não criei nada. Mande *retorno* a partir das 8h', v_i.n);
        continue;
      end if;
      v_orcamentos := v_orcamentos || jsonb_build_array(jsonb_build_object(
        'item_id', v_i.id, 'n', v_i.n, 'previa_id', v_i.previa_id, 'acao', v_i.acao_sim, 'service_order_id', v_i.service_order_id,
        'numero', case when v_i.acao_sim = 'pdf' then (select so.service_order_number from public.service_orders so where so.id = v_i.service_order_id) end,
        'rotulo', public._retorno_rotulo(v_ab.id, v_agora)));
      update public.retorno_cartao_itens i set estado = 'feito', decidido_em = v_agora where i.id = v_i.id;
      continue;
    end if;

    if v_i.texto_ditado is not null then
      v_ditados := v_ditados || jsonb_build_array(jsonb_build_object(
        'item_id', v_i.id, 'phone', v_ab.phone_normalized, 'texto', v_i.texto_ditado,
        'dedupe_key', 'retorno:' || v_ab.id || ':ditado:' || md5(v_i.texto_ditado)));
      v_n := v_n + 1;
      v_rotulos := v_rotulos || public._retorno_rotulo(v_ab.id, v_agora);
    elsif v_i.modelo_tipo is not null then
      if v_cfg.modo <> 'ligado' then
        v_frases := v_frases || 'O retorno está em teste: não mandei.'::text;
      elsif v_cfg.segura_tudo_ate is not null and v_cfg.segura_tudo_ate > v_agora then
        v_frases := v_frases || '*segura tudo* está ligado: não mandei.'::text;
      elsif exists (select 1 from public.retorno_saidas s
                     where s.abertura_id = v_ab.id and s.tipo like 'modelo\_%' escape '\'
                       and s.estado in ('agendada', 'preparada', 'enviando')) then
        v_frases := v_frases || format('o %s já está saindo', v_i.n);
      else
        select o into v_op from jsonb_array_elements(v_i.opcoes) o where o ->> 'letra' = v_i.escolha limit 1;
        insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo, estado,
                                           enviar_em, dados, dedupe_key)
        values (v_ab.id, v_i.modelo_tipo, 'aprovado', 'retorno_modelo', 'resposta_imediata', v_ab.chave, v_ab.phone_normalized, v_ab.client_id,
                'ligado', 'agendada', v_agora,
                jsonb_build_object('aprovada', true, 'aprovada_em', v_agora, 'cartao_id', p_cartao, 'item_id', v_i.id,
                                   'texto_aprovado', v_i.texto_mostrado, 'hash', v_i.hash, 'os_id', v_i.service_order_id,
                                   'marca_liberado', coalesce((v_op ->> 'marca_liberado')::boolean, false)),
                'retorno:' || v_ab.id || ':modelo:' || v_i.id)
        returning id into v_saida;
        update public.retorno_cartao_itens i set saida_id = v_saida where i.id = v_i.id;
        -- F3 (P6): *precisa ver no local* aprovado tira a proposta da mesa; a marca do caso nasce quando M07 sai (P4).
        if v_i.previa_id is not null and v_i.modelo_tipo = 'modelo_ver_no_local' then
          update public.retorno_previa p
             set estado = 'ver_no_local', decidida_em = v_agora, atualizada_em = v_agora
           where p.id = v_i.previa_id and p.estado = 'proposta';
        end if;
        if coalesce((v_op ->> 'marca_liberado')::boolean, false) and v_i.service_order_id is not null then
          update public.service_orders so
             set liberado_retirada_em = v_agora, liberado_retirada_por = p_autor
           where so.id = v_i.service_order_id;
        end if;
        v_n := v_n + 1;
        v_rotulos := v_rotulos || public._retorno_rotulo(v_ab.id, v_agora);
      end if;
    else
      update public.retorno_cartao_itens i set estado = 'fora' where i.id = v_i.id;
      continue;
    end if;

    update public.retorno_cartao_itens i set estado = 'feito', decidido_em = v_agora where i.id = v_i.id;
  end loop;

  update public.retorno_cartoes c
     set estado = 'decidido', decidido_em = v_agora, decidido_por = 'sim_pin'
   where c.id = p_cartao;
  perform public._retorno_toque('sim_pin', p_cartao, null, v_agora);

  if v_n > 0 then
    v_aviso := format('Vai sair %s: %s.', v_n, array_to_string(v_rotulos, ', '));
  elsif cardinality(v_frases) = 0 and jsonb_array_length(v_orcamentos) = 0 and jsonb_array_length(v_aceites) = 0 then   -- F5 (P7)   -- F3 (P6): orçamento não é "nada para mandar"
    v_aviso := 'Nada para mandar neste cartão. *retorno* abre de novo: use *dita N* ou a letra antes do *sim*.';
  end if;
  v_aviso := concat_ws(' ', v_aviso, nullif(array_to_string(v_frases, ' · '), ''),
                       case when v_c.mais > 0 then format('Mais %s esperando: *retorno*.', v_c.mais) end);

  return jsonb_build_object('ok', true, 'aviso', v_aviso, 'ditados', v_ditados, 'vai_sair', v_n, 'orcamentos', v_orcamentos,   -- F3 (P6)
                            'aceites', v_aceites);   -- F5 (P7)
end;
$$;
revoke all on function public.retorno_cartao_executar(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_cartao_executar(uuid, uuid, timestamptz) to service_role;

create or replace function public.retorno_ver_caso(p_n integer, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_vivo jsonb;
  v_cartao uuid;
  v_item public.retorno_cartao_itens;
  v_recebidas text;
  v_extras text;
  -- F3 (P5)
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_pv public.retorno_previa;
  v_cli uuid;
  v_unidades jsonb;
  v_lista text;
  v_validade text;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'motivo', 'nao_e_o_dono');
  end if;
  v_vivo := public.retorno_cartao_vivo(v_agora);
  if v_vivo is null then
    return jsonb_build_object('ok', true, 'texto', 'Não há lista aberta. Mande *retorno*.');
  end if;
  v_cartao := (v_vivo ->> 'id')::uuid;
  select * into v_item from public.retorno_cartao_itens i
   where i.cartao_id = v_cartao and i.n = p_n and i.estado = 'vivo';
  if not found then
    return jsonb_build_object('ok', true, 'texto', format('Não há caso %s nesta lista. Mande *retorno*.', p_n));
  end if;
  -- F5 (P7): o item do orçamento tem o *ver* dele (com caso: as mensagens do caso e os candidatos; sem caso: a mensagem do aceite
  -- ou o texto inteiro do passo, e o orçamento).
  if v_item.tipo_item in ('aceite', 'dados_nota', 'cadencia') then
    return public._orcamento_ver_item(v_item.id, p_autor, v_agora);
  end if;

  select string_agg(x.linha, E'\n' order by x.recebida_em, x.id)
    into v_recebidas
    from (select m.recebida_em, m.whatsapp_message_id as id,
                 to_char(m.recebida_em at time zone 'America/Sao_Paulo', 'HH24:MI') || ' '
                   || public._retorno_trecho(w.body, w.message_type, m.audio_pendente, 300) as linha
            from public.retorno_mensagens m
            join public.whatsapp_messages w on w.id = m.whatsapp_message_id
           where m.abertura_id = v_item.abertura_id and m.recebida_em <= v_agora
           order by m.recebida_em desc, m.whatsapp_message_id desc
           limit 5) x;

  select string_agg(btrim(l.linha), E'\n' order by l.ord)
    into v_extras
    from public.retorno_cartoes c
    cross join lateral jsonb_array_elements_text(coalesce(c.dados -> 'linhas' -> p_n::text, '[]'::jsonb)) with ordinality as l(linha, ord)
   where c.id = v_cartao and l.ord > 1
     and l.linha not like '   · %';   -- F3 (P5): as linhas C30 já vêm na lista completa, logo acima

  -- F3 (P5): a proposta viva, linha a linha, com o rótulo honesto de cada preço. Sem proposta, *ver* continua como na F2.
  if v_cfg.previa_ditado_ligado or v_cfg.previa_modo = 'ligado' then
    select p.* into v_pv from public.retorno_previa p where p.abertura_id = v_item.abertura_id and p.estado = 'proposta' limit 1;
    if found then
      select string_agg(l.ordem || '. ' || l.nome
                        || case when l.preco is not null then ' · ' || public._retorno_qtd(l.quantidade) || ' × R$ ' || public._retorno_brl(l.preco) else '' end
                        || ' · ' || public._retorno_rotulo_do_preco(l.preco_fonte, l.preco_em),
                        E'\n' order by l.ordem)
        into v_lista
        from public.retorno_previa_linhas l where l.previa_id = v_pv.id;
      v_validade := public._retorno_quando(public._retorno_validade_do_envio(v_agora), (v_agora at time zone c_fuso)::date);
      v_lista := concat_ws(E'\n',
        case when v_pv.fonte_numero is not null
             then format('Proposta com base no %s (%s):', v_pv.fonte_numero, public._retorno_mes_aa((v_pv.fonte_em at time zone c_fuso)::date))
             else 'Proposta ditada:' end,
        v_lista,
        format('Total: R$ %s · vale até %s, contado do envio', public._retorno_brl(v_pv.total), v_validade));
      v_cli := (public._retorno_cadastro_do_caso(v_item.abertura_id) ->> 'client_id')::uuid;
      v_unidades := public._retorno_unidades_do_cliente(v_cli);
      if v_pv.vessel_id is null and (public._retorno_unidade_do_caso(v_item.abertura_id, v_cli, v_agora) ->> 'vessel_id') is null
         and jsonb_array_length(v_unidades) >= 2 then
        v_lista := v_lista || E'\n' || 'Unidades: '
          || (select string_agg(format('%s. %s', u ->> 'numero', u ->> 'nome'), ' · ' order by (u ->> 'numero')::integer) from jsonb_array_elements(v_unidades) u);
      end if;
    end if;
  end if;

  perform public._retorno_toque('ver', v_cartao, v_item.abertura_id, v_agora);

  return jsonb_build_object('ok', true,
    'texto', concat_ws(E'\n', format('%s · %s', public._retorno_rotulo(v_item.abertura_id, v_agora),
                                     public._retorno_prazo_curto(v_item.abertura_id, v_agora)),
                       v_recebidas, v_lista, v_extras),
    'historico', jsonb_build_object('user', format('(ver %s)', p_n),
                                    'assistant', format('(mostrei o caso %s ao dono)', p_n)));
end;
$$;
revoke all on function public.retorno_ver_caso(integer, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_ver_caso(integer, uuid, timestamptz) to service_role;

create or replace function public.retorno_destino_do_item(p_n integer, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_vivo jsonb;
  v_i public.retorno_cartao_itens;
  v_ab public.retorno_aberturas;
  v_conf jsonb;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('erro', 'Só o dono responde o caso.');
  end if;
  v_vivo := public.retorno_cartao_vivo(v_agora);
  if v_vivo is null or v_vivo ->> 'estado' <> 'vivo' then
    return jsonb_build_object('erro', 'Não há cartão aberto.');
  end if;
  select * into v_i from public.retorno_cartao_itens i
   where i.cartao_id = (v_vivo ->> 'id')::uuid and i.n = p_n and i.estado = 'vivo';
  if not found then
    return jsonb_build_object('erro', format('O cartão não tem o caso %s.', p_n));
  end if;
  -- F5 (P7): item sem conversa aberta não tem destino: o ditado por áudio (retorno_responder_caso) e o retorno_ler_caso recusam.
  if v_i.abertura_id is null then
    return jsonb_build_object('erro', 'Este item não tem conversa aberta: responda pelo assistente.');
  end if;
  select * into v_ab from public.retorno_aberturas a where a.id = v_i.abertura_id;
  v_conf := public._retorno_item_conferir(v_i.id, v_agora, false);
  return jsonb_build_object('item_id', v_i.id, 'abertura_id', v_ab.id, 'phone', v_ab.phone_normalized,
                            'rotulo', public._retorno_rotulo(v_ab.id, v_agora),
                            'ok', (v_conf ->> 'ok')::boolean, 'texto', v_conf ->> 'texto');
end;
$$;
revoke all on function public.retorno_destino_do_item(integer, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_destino_do_item(integer, uuid, timestamptz) to service_role;

CREATE OR REPLACE FUNCTION public._retorno_dito_pessoal(p_n integer, p_autor uuid, p_agora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_vivo jsonb;
  v_cartao uuid;
  v_vivos integer;
  v_item public.retorno_cartao_itens;
  v_ab public.retorno_aberturas;
  v_antes text;
  v_rotulo text;
begin
  v_vivo := public.retorno_cartao_vivo(p_agora);
  if v_vivo is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;
  v_cartao := (v_vivo ->> 'id')::uuid;

  select count(*) into v_vivos from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo';
  if p_n is null then
    if v_vivos = 0 then
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
    end if;
    if v_vivos > 1 then
      return jsonb_build_object('ok', true, 'texto', 'Qual? *pessoal 2*.');
    end if;
    select * into v_item from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo';
  else
    select * into v_item from public.retorno_cartao_itens i
     where i.cartao_id = v_cartao and i.n = p_n and i.estado = 'vivo';
    if not found then
      return jsonb_build_object('ok', true, 'texto', format('Não há caso %s nesta lista. Mande *retorno*.', p_n));
    end if;
  end if;

  -- F5 (P7): *pessoal N* é sobre o número de uma conversa. Item sem caso recusa; no aceite ou nos dados com caso, vale como na F2,
  -- e o aceite cai (o número virou pessoal).
  if v_item.abertura_id is null then
    return jsonb_build_object('ok', true,
      'texto', format('O %s não é uma conversa: *pessoal* vale só para caso. Use *não %s*.', v_item.n, v_item.n));
  end if;
  if v_item.aceite_id is not null then
    perform public._orcamento_item_pessoal(v_item.id, p_agora);
  end if;
  select * into v_ab from public.retorno_aberturas a where a.id = v_item.abertura_id;
  v_rotulo := public._retorno_rotulo(v_ab.id, p_agora);

  select l.lead_tipo into v_antes from public.whatsapp_leads l where l.phone_normalized = v_ab.phone_normalized;
  insert into public.whatsapp_leads (phone_normalized, status, lead_tipo)
  values (v_ab.phone_normalized, 'discarded', 'pessoal')
  on conflict (phone_normalized) do update set lead_tipo = 'pessoal', updated_at = now();

  update public.retorno_saidas s
     set estado = 'cancelada', motivo = 'pessoal', decidida_em = p_agora, atualizada_em = now()
   where s.abertura_id = v_ab.id and s.estado = 'agendada';

  update public.retorno_aberturas a
     set estado = 'fechada', fechada_em = p_agora, fechada_motivo = 'nada', atualizada_em = now()
   where a.id = v_ab.id and a.estado <> 'fechada';

  update public.retorno_cartao_itens i
     set estado = 'caiu', caiu_motivo = 'caso_fechado', decidido_em = p_agora
   where i.id = v_item.id;

  update public.retorno_cartoes c
     set texto = public._retorno_cartao_texto(c.id, null)
   where c.id = v_cartao;

  update public.retorno_config
     set pessoal_ultimo = jsonb_build_object('phone', v_ab.phone_normalized, 'lead_tipo_antes', v_antes, 'em', p_agora),
         atualizado_em = now(), atualizado_por = p_autor where id;

  perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('lead_tipo', v_antes),
    jsonb_build_object('lead_tipo', 'pessoal', 'abertura', v_ab.id), '*pessoal* do dono');
  perform public._retorno_toque('pessoal', v_cartao, v_ab.id, p_agora);

  return jsonb_build_object('ok', true,
    'texto', format('%s: anotado como pessoal. Esse número nunca mais recebe automático, e cancelei o que estava agendado. *pessoal não* desfaz.', v_rotulo));
end;
$function$;
revoke all on function public._retorno_dito_pessoal(integer, uuid, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_dito_resolvido(p_n integer, p_autor uuid, p_agora timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vivo jsonb;
  v_cartao uuid;
  v_item public.retorno_cartao_itens;
  v_ab public.retorno_aberturas;
  v_rotulo text;
  v_k integer;
  v_f5 jsonb;   -- F5 (P7)
begin
  if p_n is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;
  v_vivo := public.retorno_cartao_vivo(p_agora);
  if v_vivo is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;
  v_cartao := (v_vivo ->> 'id')::uuid;

  select * into v_item from public.retorno_cartao_itens i
   where i.cartao_id = v_cartao and i.n = p_n and i.estado = 'vivo';
  if not found then
    return jsonb_build_object('ok', true, 'texto', format('Não há caso %s nesta lista. Mande *retorno*.', p_n));
  end if;

  -- F5 (P7): *resolvido N* no item do orçamento: cadência → passo pulado/tirado; aceite → nao_era; dados → nada. Sem caso, a
  -- resposta é a da F5, com o rótulo do orçamento; com caso, a F2 segue e fecha o caso.
  if v_item.tipo_item in ('aceite', 'dados_nota', 'cadencia') then
    v_f5 := public._orcamento_item_resolvido(v_item.id, p_autor, p_agora);
    if v_item.abertura_id is null then
      return v_f5;
    end if;
  end if;
  select * into v_ab from public.retorno_aberturas a where a.id = v_item.abertura_id for update;
  v_rotulo := public._retorno_rotulo(v_ab.id, p_agora);

  update public.retorno_saidas s
     set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = p_agora, atualizada_em = now()
   where s.abertura_id = v_ab.id and s.estado = 'agendada';
  get diagnostics v_k = row_count;

  update public.retorno_aberturas a
     set estado = 'fechada', fechada_em = p_agora, fechada_motivo = 'dono', atualizada_em = now()
   where a.id = v_ab.id and a.estado <> 'fechada';

  update public.retorno_cartao_itens i
     set estado = 'caiu', caiu_motivo = 'caso_fechado', decidido_em = p_agora
   where i.id = v_item.id;

  update public.retorno_cartoes c
     set texto = public._retorno_cartao_texto(c.id, null)
   where c.id = v_cartao;

  perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('estado', v_ab.estado),
    jsonb_build_object('estado', 'fechada', 'fechada_motivo', 'dono', 'abertura', v_ab.id), '*resolvido* do dono');
  perform public._retorno_toque('resolvido', v_cartao, v_ab.id, p_agora);

  return jsonb_build_object('ok', true,
    'texto', case when v_k = 0 then format('%s: resolvido, saiu da lista.', v_rotulo)
                  else format('%s: resolvido, saiu da lista, e cancelei o que estava agendado para ele.', v_rotulo) end);
end;
$$;
revoke all on function public._retorno_dito_resolvido(integer, uuid, timestamptz) from public, anon, authenticated;

create or replace function public.retorno_item_enviado(p_item uuid, p_ok boolean, p_wa_id text default null, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_i public.retorno_cartao_itens;
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item for update;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  if not p_ok then
    update public.retorno_cartao_itens i set estado = 'fora' where i.id = p_item;
    return jsonb_build_object('ok', true);
  end if;
  -- F5 (P7): o ditado no item de aceite (ou de dados) saiu: o aceite fica 'respondido' (os dados, 'nada'); o orçamento fica como está.
  if v_i.aceite_id is not null then
    perform public._orcamento_ditado_enviado(v_i.id, v_agora);
  end if;
  -- Ditado curto não cumpre pela régua da F1 (15 caracteres), e o cliente ouviria o adiamento depois da resposta do dono.
  update public.retorno_aberturas a
     set cumprida_em = coalesce(a.cumprida_em, v_agora), cumprida_por = coalesce(a.cumprida_por, 'cartao'),
         estado = 'fechada', fechada_em = coalesce(a.fechada_em, v_agora), fechada_motivo = coalesce(a.fechada_motivo, 'conteudo'),
         atualizada_em = now()
   where a.id = v_i.abertura_id;
  update public.retorno_saidas s
     set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_agora, atualizada_em = now()
   where s.abertura_id = v_i.abertura_id and s.estado = 'agendada';
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.retorno_item_enviado(uuid, boolean, text, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_item_enviado(uuid, boolean, text, timestamptz) to service_role;

create or replace function public._retorno_tem_orcamento(p_abertura uuid, p_agora timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.retorno_aberturas a
      join public.service_orders so on so.client_id = a.client_id
     where a.id = p_abertura
       and so.status = 'draft'
       and so.quote_status = 'draft'
       and so.merged_into_id is null
       and not exists (select 1 from public.orcamento_envios e where e.service_order_id = so.id)   -- F5 (P7): enviado não está "em preparação"
       and so.created_at >= a.aberta_em - interval '14 days'
       and so.created_at <= p_agora);
$$;
revoke all on function public._retorno_tem_orcamento(uuid, timestamptz) from public, anon, authenticated;
