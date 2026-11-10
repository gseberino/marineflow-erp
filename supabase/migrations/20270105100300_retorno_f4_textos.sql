-- Retorno rápido ao cliente, F4 (P4): os textos do parceiro e do aviso ao cliente final, e o contexto do validador.
-- Gerada por script (scripts/gerar_f4.cjs textos): as funções novas vêm de scripts/f4_sql/p4_textos.sql, escritas à mão;
-- _cliente_ja_apresentada é gerada do corpo vigente, e só o trecho marcado -- F4 é novo.
--
-- 1. _parceiro_nome_curto ("João S."), _parceiro_bem (palavra fechada e masculina, só por asset_type), _parceiro_bem_do_par,
--    _parceiro_ja_apresentada e _parceiro_abertura (o prefixo {comigo} na 1ª mensagem ao número, {pessoa} depois; nunca os
--    dois).
-- 2. _parceiro_nomes_do_contexto: nomes_da_lista, nomes_de_outros (sem as palavras fixas Gustavo, Claudia, HBR e a sigla),
--    nome_permitido e pessoa_ok (P4.2).
-- 3. _parceiro_texto: o catálogo P01–P16, as linhas do painel e do pátio, Q01–Q05 e Q03/Q03b. Gênero: o nome sempre com
--    "de", e "o cliente" no lugar de pronome. P04 sem nome também sem pronome (desvio registrado na entrega da P4).
-- 4. _parceiro_contexto_do_validador: o contexto de validarSaidaAoParceiro (e de validarSaida nos Q). Chama
--    _parceiro_cliente_ouviu (P7) só quando há linha que afirma "avisado"; plpgsql, compila na 1ª execução.
-- 5. _cliente_ja_apresentada (gerada): o aviso ao cliente final enviado conta como apresentação.
--
-- Sem dado. Nada aqui é chamado enquanto parceiro_modo = 'desligado' (o padrão) e nenhum tipo do parceiro está ligado.
-- Reverter: reaplicar _cliente_ja_apresentada de 20261208100300; depois, drop function das sete funções _parceiro_* desta
-- migration.

-- ── 1. O nome curto, a palavra do bem e a apresentação ao número ────────────────────────────────────────────────────────

-- "João S.": o 1º nome e a inicial da última palavra que não é partícula. Nome único: só o 1º nome. Empresa e provisório:
-- só o nome curto (a OS da própria parceira sai "MP"). Cliente genérico: nulo, e a linha fica de fora (P7.2).
create or replace function public._parceiro_nome_curto(p_client uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_c public.clients;
  v_base text;
  v_primeiro text;
  v_ultima text;
  v_inicial text;
begin
  select * into v_c from public.clients c where c.id = p_client;
  if not found or coalesce(v_c.generico, false) then
    return null;
  end if;
  v_base := coalesce(nullif(btrim(v_c.display_name), ''), v_c.name);
  v_primeiro := public._agenda_nome_curto(v_base);
  if v_primeiro is null then
    return null;
  end if;
  if v_c.type = 'company' or coalesce(v_c.provisorio, false) then
    return v_primeiro;
  end if;
  select x.w into v_ultima
    from unnest((regexp_split_to_array(btrim(v_base), '[[:space:]]+'))[2:]) with ordinality as x(w, i)
   where public._texto_simples(x.w) not in ('da', 'de', 'di', 'do', 'das', 'dos', 'e')
   order by x.i desc
   limit 1;
  v_inicial := left(coalesce(v_ultima, ''), 1);
  if v_inicial !~ '^[A-Za-zÀ-ÖØ-öø-ÿ]$' then
    return v_primeiro;
  end if;
  return v_primeiro || ' '
      || translate(upper(v_inicial), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ') || '.';
end;
$$;

comment on function public._parceiro_nome_curto(uuid) is
  'Retorno F4 (P4.1): o nome do cliente como o parceiro lê ("João S."): 1º nome e a inicial da última palavra que não é partícula (da, de, di, do, das, dos, e); nome único, empresa e provisório só o 1º nome; genérico nulo.';

revoke all on function public._parceiro_nome_curto(uuid) from public, anon, authenticated;

-- A palavra do bem, fechada e masculina ("o {bem}", "seu {bem}"). Só lê vessels.asset_type: nunca name, model,
-- manufacturer nem a placa.
create or replace function public._parceiro_bem(p_vessel uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when x.t in ('motorhome', 'motor home') then 'motorhome'
    when x.t = 'trailer' then 'trailer'
    when x.t = 'camper' then 'camper'
    when x.t in ('lancha', 'veleiro', 'catamara', 'jet ski', 'moto aquatica', 'barco', 'embarcacao', 'outra embarcacao',
                 'escuna', 'traineira', 'bote') then 'barco'
    else 'veículo'
  end
  from (select public._texto_simples(btrim(coalesce((select v.asset_type from public.vessels v where v.id = p_vessel), ''))) as t) x;
$$;

comment on function public._parceiro_bem(uuid) is
  'Retorno F4 (P4.1): motorhome, trailer, camper, barco (o grupo embarcação de unidade.ts) ou veículo (o resto e unidade nula), só por vessels.asset_type.';

revoke all on function public._parceiro_bem(uuid) from public, anon, authenticated;

-- A palavra do par no aviso ao cliente: uma só entre os vínculos comerciais confirmados, ela; palavras diferentes, veículo.
create or replace function public._parceiro_bem_do_par(p_client uuid, p_parceiro uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case when count(distinct x.b) = 1 then min(x.b) else 'veículo' end
    from (select public._parceiro_bem(so.vessel_id) as b
            from public.os_interessados oi
            join public.service_orders so on so.id = oi.service_order_id
           where oi.client_id = p_client
             and oi.parceiro_id = p_parceiro
             and oi.situacao = 'confirmado'
             and oi.papel is distinct from 'anfitria') x;
$$;

comment on function public._parceiro_bem_do_par(uuid, uuid) is
  'Retorno F4 (P4.1): a palavra do bem no aviso ao cliente (Q01–Q05): a de _parceiro_bem, quando os vínculos comerciais confirmados do par têm uma só; senão, veículo.';

revoke all on function public._parceiro_bem_do_par(uuid, uuid) from public, anon, authenticated;

-- O número já ouviu a apresentação ("Claudia, assistente virtual") dentro de apresentacao_intervalo? Ninguém olha o futuro.
create or replace function public._parceiro_ja_apresentada(p_numero uuid, p_agora timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select n.apresentada_em is not null
                          and n.apresentada_em <= coalesce(p_agora, now())
                          and n.apresentada_em > coalesce(p_agora, now())
                              - coalesce((public._retorno_cfg()).apresentacao_intervalo, interval '365 days')
                     from public.parceiro_numeros n
                    where n.id = p_numero), false);
$$;

comment on function public._parceiro_ja_apresentada(uuid, timestamptz) is
  'Retorno F4 (P4.1): parceiro_numeros.apresentada_em dentro de retorno_config.apresentacao_intervalo, até p_agora. Em sombra apresentada_em não é gravada, e a simulação sai sempre com a apresentação.';

revoke all on function public._parceiro_ja_apresentada(uuid, timestamptz) from public, anon, authenticated;

-- O prefixo {comigo}{pessoa}, já com o espaço final, ou vazio. Os dois nunca saem juntos: na 1ª mensagem ao número,
-- {comigo}; depois, {pessoa}. O nome só sai com pessoa_ok: o 1º nome da pessoa não é uma entrada inteira de p_outros (os
-- nomes_de_outros do contexto). p_outros que não é lista: sem nome (falha fecha).
create or replace function public._parceiro_abertura(p_numero uuid, p_outros jsonb, p_agora timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pessoa_nome text;
  v_nome text;
  v_ok boolean;
begin
  select p.nome into v_pessoa_nome
    from public.parceiro_numeros n
    join public.parceiro_pessoas p on p.id = n.pessoa_id
   where n.id = p_numero;
  if not found then
    raise exception using errcode = '22023', message = 'parceiro_abertura: número desconhecido';
  end if;
  v_nome := public._agenda_nome_curto(v_pessoa_nome);
  v_ok := v_nome is not null
          and v_nome ~ '^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ''-]{0,39}$'
          and jsonb_typeof(p_outros) = 'array'
          and not exists (select 1 from jsonb_array_elements_text(p_outros) o
                           where public._texto_simples(btrim(o)) = public._texto_simples(v_nome));
  if not public._parceiro_ja_apresentada(p_numero, p_agora) then
    return (case when v_ok then v_nome || ', aqui é a Claudia, assistente virtual da HBR. '
                 else 'Aqui é a Claudia, assistente virtual da HBR. ' end);
  end if;
  return (case when v_ok then 'Oi, ' || v_nome || '! ' else '' end);
end;
$$;

comment on function public._parceiro_abertura(uuid, jsonb, timestamptz) is
  'Retorno F4 (P4.1): o prefixo dos textos ao parceiro. 1ª mensagem ao número: "Carla, aqui é a Claudia, assistente virtual da HBR. " (ou "Aqui é a Claudia, ..." sem nome ou sem pessoa_ok); depois: "Oi, Carla! " ou vazio. Sempre com o espaço final, ou vazio.';

revoke all on function public._parceiro_abertura(uuid, jsonb, timestamptz) from public, anon, authenticated;

-- ── 2. As duas listas de nomes do validador (P4.2) ──────────────────────────────────────────────────────────────────────

-- nomes_da_lista: as formas de p_clientes (os clientes das linhas que vão sair). nomes_de_outros: as formas dos outros
-- clientes com linha em os_interessados do parceiro, em qualquer situação, menos as que estão na lista e as palavras fixas
-- dos modelos (Gustavo, Claudia, HBR e a sigla). nome_permitido: o 1º nome da pessoa do parceiro, que nunca entra na lista;
-- pessoa_ok falso quando ele é uma entrada inteira de nomes_de_outros. Comparação em _texto_simples.
create or replace function public._parceiro_nomes_do_contexto(p_parceiro uuid, p_clientes uuid[], p_pessoa uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_clientes uuid[] := coalesce(p_clientes, '{}'::uuid[]);
  v_fixas text[];
  v_lista text[];
  v_outros text[];
  v_nome text;
  v_ok boolean;
begin
  select array['gustavo', 'claudia', 'hbr'] || coalesce(array[public._texto_simples(btrim(pa.sigla))], '{}'::text[])
    into v_fixas
    from public.parceiros pa
   where pa.id = p_parceiro;
  v_fixas := coalesce(v_fixas, array['gustavo', 'claudia', 'hbr']);

  select coalesce(array_agg(y.f order by y.primeira), '{}'::text[]) into v_lista
    from (select x.f, min(x.i) as primeira
            from (select public._parceiro_nome_curto(u.c) as f, u.i
                    from unnest(v_clientes) with ordinality as u(c, i)) x
           where x.f is not null
           group by x.f) y;

  select coalesce(array_agg(distinct y.f order by y.f), '{}'::text[]) into v_outros
    from (select public._parceiro_nome_curto(o.client_id) as f
            from (select distinct oi.client_id
                    from public.os_interessados oi
                   where oi.parceiro_id = p_parceiro
                     and not (oi.client_id = any (v_clientes))) o) y
   where y.f is not null
     and public._texto_simples(btrim(y.f)) <> all (array(select public._texto_simples(btrim(l)) from unnest(v_lista) as l))
     and public._texto_simples(btrim(y.f)) <> all (v_fixas);

  select public._agenda_nome_curto(p.nome) into v_nome from public.parceiro_pessoas p where p.id = p_pessoa;
  v_ok := v_nome is not null
          and not exists (select 1 from unnest(v_outros) as o
                           where public._texto_simples(btrim(o)) = public._texto_simples(v_nome));

  return jsonb_build_object('nomes_da_lista', to_jsonb(v_lista), 'nomes_de_outros', to_jsonb(v_outros),
                            'nome_permitido', v_nome, 'pessoa_ok', coalesce(v_ok, false));
end;
$$;

comment on function public._parceiro_nomes_do_contexto(uuid, uuid[], uuid) is
  'Retorno F4 (P4.2): {nomes_da_lista, nomes_de_outros, nome_permitido, pessoa_ok} para o validador do texto ao parceiro. Outros = clientes do parceiro em os_interessados (qualquer situação) fora de p_clientes, menos os da lista e as palavras fixas (Gustavo, Claudia, HBR, a sigla).';

revoke all on function public._parceiro_nomes_do_contexto(uuid, uuid[], uuid) from public, anon, authenticated;

-- ── 3. O catálogo (P4.1). Falta de dado ou valor fora da lista = 22023, como _retorno_texto ────────────────────────────

-- Campos: {abertura} (o prefixo de _parceiro_abertura; {comigo} é ele só na forma da 1ª mensagem), {quando_fala} (de
-- quando + hora, como _retorno_texto), {nome}, {sigla}, {bem} (lista fechada), {cliente} (o nome curto, "João S."),
-- {primeiro_nome} (o nome do cliente dito ou do cadastro) e {validade} (dd/mm). As linhas do painel e do pátio são a
-- variante 'linha' (n, bem, cliente, estado, desde); o painel, o pátio e o bloco P11 recebem as linhas já prontas.
create or replace function public._parceiro_texto(p_tipo text, p_variante text, p_dados jsonb)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_dia constant text := '^(hoje|amanhã|(segunda|terça|quarta|quinta|sexta|sábado|domingo) \([0-9]{2}/[0-9]{2}\))$';
  c_hora constant text := '^[0-9]{1,2}h$|^[0-9]{2}:[0-9]{2}$';
  c_nome constant text := '^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ .''-]{0,39}$';
  c_abertura constant text :=
    '^(Aqui é a Claudia, assistente virtual da HBR\. |[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ''-]{0,39}, aqui é a Claudia, assistente virtual da HBR\. |Oi, [A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ''-]{0,39}! )?$';
  c_linha constant text := '^[1-9][0-9]?\. [^[:cntrl:]]+\.$';
  c_bens constant text[] := array['motorhome', 'trailer', 'camper', 'barco', 'veículo'];
  c_dias constant text[] := array['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_variante text := coalesce(nullif(btrim(p_variante), ''), 'padrao');
  v_modelo text;
  v_texto text;
  v_campo text;
  v_valor text;
  v_parte text;
  v_ok boolean;
  v_papel text;
  v_sem_nome boolean := false;
  v_outros jsonb;
  v_dia date;
  v_desde date;
  v_situacao text;
  v_linhas text[];
  v_mais integer := 0;
begin
  -- ── As linhas do painel e do pátio (P7.2): "n. {Bem} de {cliente}: {situação}." ──
  if p_tipo in ('parceiro_painel', 'parceiro_patio') and v_variante = 'linha' then
    if coalesce(d ->> 'n', '') !~ '^[1-9][0-9]?$' then
      raise exception using errcode = '22023', message = 'parceiro_texto: falta n';
    end if;
    v_valor := btrim(d ->> 'bem');
    if v_valor is null or not (v_valor = any (c_bens)) then
      raise exception using errcode = '22023', message = 'parceiro_texto: valor fora da lista em bem';
    end if;
    v_parte := btrim(d ->> 'cliente');
    if coalesce(v_parte, '') !~ c_nome then
      raise exception using errcode = '22023', message = 'parceiro_texto: valor fora da lista em cliente';
    end if;
    if jsonb_typeof(d -> 'desde') = 'string' then
      begin
        v_desde := (d ->> 'desde')::date;
      exception when others then
        raise exception using errcode = '22023', message = 'parceiro_texto: desde inválido';
      end;
    end if;
    v_situacao := case d ->> 'estado'
      when 'pronto' then 'pronto; o cliente já foi avisado para combinar a retirada'
      when 'peca_chegou' then (case when v_desde is not null then 'a peça chegou em ' || to_char(v_desde, 'DD/MM') end)
      when 'aguarda_peca' then (case when v_desde is not null then 'aguardando uma peça; sem novidade desde ' || to_char(v_desde, 'DD/MM')
                                     else 'aguardando uma peça' end)
      when 'em_servico' then 'em serviço hoje'
      when 'andamento' then (case when v_desde is not null then 'sem novidade desde ' || to_char(v_desde, 'DD/MM') end)
      when 'andamento_sem_data' then 'em serviço'
      when 'orcamento' then 'orçamento pedido por vocês; com o Gustavo'
      -- R2 (resposta ao F4-14): só com retorno_config.parceiro_sem_inicio_ligado, lida pelo jsonb da linha de config porque
      -- a coluna nasce na P7 (onda 5); ausente ou falsa, sem texto (22023), e a linha sai da saída já agendada
      when 'sem_inicio' then (case when coalesce((to_jsonb(public._retorno_cfg()) ->> 'parceiro_sem_inicio_ligado')::boolean, false)
                                   then 'aguardando o início do serviço' end)
    end;
    if v_situacao is null then
      raise exception using errcode = '22023', message = 'parceiro_texto: estado da linha desconhecido ou sem a data';
    end if;
    return (d ->> 'n') || '. ' || upper(left(v_valor, 1)) || substr(v_valor, 2) || ' de ' || v_parte || ': ' || v_situacao || '.';
  end if;

  -- ── O painel (P06) e o pátio direto (P10): cabeçalho, as linhas prontas e "E mais" ──
  if (p_tipo = 'parceiro_painel' and v_variante = 'padrao') or (p_tipo = 'parceiro_patio' and v_variante = 'direto') then
    begin
      v_dia := (d ->> 'dia')::date;
    exception when others then
      raise exception using errcode = '22023', message = 'parceiro_texto: dia inválido';
    end;
    if v_dia is null then
      raise exception using errcode = '22023', message = 'parceiro_texto: falta dia';
    end if;
    v_linhas := array(select x from jsonb_array_elements_text(case when jsonb_typeof(d -> 'linhas') = 'array'
                                                                    then d -> 'linhas' else '[]'::jsonb end) as x);
    if cardinality(v_linhas) = 0 or cardinality(v_linhas) > 14 then
      raise exception using errcode = '22023', message = 'parceiro_texto: o painel leva de 1 a 14 linhas';
    end if;
    if exists (select 1 from unnest(v_linhas) as l where l !~ c_linha) then
      raise exception using errcode = '22023', message = 'parceiro_texto: linha fora do formato';
    end if;
    if d ? 'mais' then
      if coalesce(d ->> 'mais', '') !~ '^[0-9]{1,3}$' then
        raise exception using errcode = '22023', message = 'parceiro_texto: valor fora da lista em mais';
      end if;
      v_mais := (d ->> 'mais')::integer;
    end if;
    v_texto := (case when p_tipo = 'parceiro_painel'
                     then 'Pátio HBR · ' || c_dias[extract(dow from v_dia)::integer + 1] || ' (' || to_char(v_dia, 'DD/MM') || ')'
                     else 'Pátio HBR · ' || to_char(v_dia, 'DD/MM') end)
               || E'\n' || array_to_string(v_linhas, E'\n');
    if v_mais > 0 then
      v_texto := v_texto || E'\n' || (case when v_mais = 1 then 'E mais 1 veículo.' else 'E mais ' || v_mais || ' veículos.' end);
    end if;
    if p_tipo = 'parceiro_painel' then
      v_texto := v_texto || E'\nPara ver de novo, mande *pátio*.';
      if d -> 'rodape' = 'true'::jsonb then
        v_texto := v_texto || E'\nValores e dados ficam com cada cliente.';
      end if;
    end if;
    return v_texto;
  end if;

  -- ── Ao cliente final: o papel do par decide Q01/Q02 (indicou) ou Q04/Q05 (contratante ou pagador) ──
  if p_tipo = 'parceiro_aviso_cliente' then
    v_papel := d ->> 'papel';
    if v_papel is null or v_papel not in ('indicou', 'contratante', 'pagador') then
      raise exception using errcode = '22023', message = 'parceiro_texto: falta papel';
    end if;
    if v_variante not in ('com_apresentacao', 'seguinte', 'contrata_com_apresentacao', 'contrata_seguinte') then
      raise exception using errcode = '22023', message = format('parceiro_texto: modelo desconhecido %s/%s', p_tipo, v_variante);
    end if;
    if v_variante like 'contrata%' and v_papel = 'indicou' then
      raise exception using errcode = '22023', message = 'parceiro_texto: quem só indicou não contrata';
    end if;
    v_modelo := (case
      when v_papel = 'indicou' and v_variante like '%com_apresentacao' then   -- Q01
        '{nome}, aqui é a Claudia, assistente virtual da HBR. Como você veio pela {sigla}, ela também acompanha o andamento do seu {bem}, sem valores. Se preferir que não, responda NÃO {sigla}.'
      when v_papel = 'indicou' then   -- Q02
        '{nome}, como você veio pela {sigla}, ela também acompanha o andamento do seu {bem}, sem valores. Se preferir que não, responda NÃO {sigla}.'
      when v_variante like '%com_apresentacao' then   -- Q04
        '{nome}, aqui é a Claudia, assistente virtual da HBR. Este serviço no seu {bem} está sendo feito por meio da {sigla}, e ela acompanha o andamento. Se preferir que não, responda NÃO {sigla}.'
      else   -- Q05
        '{nome}, este serviço no seu {bem} está sendo feito por meio da {sigla}, e ela acompanha o andamento. Se preferir que não, responda NÃO {sigla}.'
    end);
  end if;

  -- ── P04 e P15: o nome dito pela parceira sai só se não for uma entrada inteira de nomes_de_outros (P4.2, item 5) ──
  if (p_tipo = 'parceiro_coleta' and v_variante = 'whatsapp') or (p_tipo = 'parceiro_recibo' and v_variante = 'orcamento') then
    v_valor := nullif(btrim(d ->> 'primeiro_nome'), '');
    if v_valor is null then
      v_sem_nome := true;
    else
      v_outros := (case when jsonb_typeof(d -> 'nomes_de_outros') = 'array' then d -> 'nomes_de_outros'
                        when nullif(d ->> 'parceiro_id', '') is not null
                          then public._parceiro_nomes_do_contexto((d ->> 'parceiro_id')::uuid, '{}'::uuid[], null) -> 'nomes_de_outros'
                   end);
      if v_outros is null then
        raise exception using errcode = '22023', message = 'parceiro_texto: falta nomes_de_outros ou parceiro_id';
      end if;
      v_sem_nome := exists (select 1 from jsonb_array_elements_text(v_outros) as o
                             where public._texto_simples(btrim(o)) = public._texto_simples(v_valor));
    end if;
  end if;

  if v_modelo is null then
    v_modelo := (case p_tipo || '/' || v_variante
      when 'parceiro_ativacao/padrao' then   -- P01: só {comigo}
        '{comigo}A partir de agora, no fim de cada dia útil em que algo mudar, mando um resumo dos motorhomes dos clientes de vocês que estão com a gente: o que andou e o próximo passo. Valores e dados ficam com cada cliente. A qualquer hora, mande *pátio*. Para pausar, mande *pausar*.'
      when 'parceiro_recibo/padrao' then   -- P02 (o bloco P11 entra abaixo)
        '{abertura}Já passei sua mensagem ao Gustavo, e ele retorna para vocês {quando_fala}.'
      when 'parceiro_coleta/veiculo_nome' then   -- P03
        '{abertura}Já passei seu pedido ao Gustavo, e ele retorna para vocês {quando_fala}. Para adiantar: qual é o veículo e o primeiro nome do cliente?'
      when 'parceiro_coleta/whatsapp' then   -- P04
        (case when v_sem_nome
              then 'O cliente tem WhatsApp? Se autorizar, me passa o número que o Gustavo fala direto.'
              else 'Obrigada! {primeiro_nome} tem WhatsApp? Se o cliente autorizar, me passa o número que o Gustavo fala direto.' end)
      when 'parceiro_recado/padrao' then   -- P05
        (case when coalesce(btrim(d ->> 'nome'), '') = ''
              then 'Anotado. Antes de começar, confirmo com o cliente e com o Gustavo e aviso vocês.'
              else 'Anotado, {nome}. Antes de começar, confirmo com o cliente e com o Gustavo e te aviso.' end)
      when 'parceiro_eco/pronto' then   -- P07
        'Pátio HBR: o {bem} de {cliente} ficou pronto. O cliente já foi avisado para combinar a retirada.'
      when 'parceiro_eco/atraso' then   -- P08
        'Pátio HBR: o serviço no {bem} de {cliente} vai atrasar porque uma peça não chegou. O cliente já foi avisado.'
      when 'parceiro_eco/peca_chegou' then   -- P09
        'Pátio HBR: a peça do {bem} de {cliente} chegou. O cliente já foi avisado.'
      when 'parceiro_patio/vazio' then   -- P10, sem linhas
        'Pátio HBR: nenhum veículo dos clientes de vocês por aqui agora.'
      when 'parceiro_pausa/pausar' then   -- P12
        'Combinado: o resumo fica pausado. Para voltar, mande *retomar*.'
      when 'parceiro_pausa/retomar' then   -- P13
        'Pronto: o resumo volta no próximo dia útil em que algo mudar.'
      when 'parceiro_repassar/padrao' then   -- P14
        '{abertura}{primeiro_nome} não tem WhatsApp com a gente. Pode repassar esta mensagem? "{primeiro_nome}, o serviço no seu {bem} terminou. O Gustavo combina com você o melhor dia para buscar." Se o cliente autorizar, me passa o WhatsApp que o Gustavo fala direto.'
      when 'parceiro_recibo/orcamento' then   -- P15
        (case when v_sem_nome
              then '{abertura}O orçamento do {bem} do cliente está com o Gustavo; ele retorna para vocês {quando_fala}.'
              else '{abertura}O orçamento do {bem} de {primeiro_nome} está com o Gustavo; ele retorna para vocês {quando_fala}.' end)
      when 'parceiro_legenda/padrao' then   -- P16, a legenda do PDF ao parceiro
        '{abertura}Segue o orçamento do {bem} de {primeiro_nome}, válido até {validade}.'
      when 'parceiro_nao_mp_ok/com_nome' then   -- Q03
        'Combinado, {nome}: o andamento fica só entre nós.'
      when 'parceiro_nao_mp_ok/sem_nome' then   -- Q03b
        'Combinado: o andamento fica só entre nós.'
    end);
  end if;
  if v_modelo is null then
    raise exception using errcode = '22023',
      message = format('parceiro_texto: modelo desconhecido %s/%s', coalesce(p_tipo, '(nenhum)'), v_variante);
  end if;

  -- Cada {campo} do modelo, na ordem em que aparece: presente, não vazio e dentro da lista fechada. Nenhum valor aceito tem
  -- chave, então a troca de um campo nunca cria outro campo.
  v_texto := v_modelo;
  for v_campo in
    select x.m[1] from regexp_matches(v_modelo, '\{([a-z_]+)\}', 'g') with ordinality as x(m, n)
     group by x.m[1] order by min(x.n)
  loop
    if v_campo = 'quando_fala' then
      foreach v_parte in array array['quando', 'hora'] loop
        v_valor := btrim(d ->> v_parte);
        if coalesce(v_valor, '') = '' then
          raise exception using errcode = '22023', message = 'parceiro_texto: falta ' || v_parte;
        end if;
        if v_valor !~ (case v_parte when 'quando' then c_dia else c_hora end) then
          raise exception using errcode = '22023', message = 'parceiro_texto: valor fora da lista em ' || v_parte;
        end if;
      end loop;
      v_valor := public._retorno_quando_fala(btrim(d ->> 'quando'), btrim(d ->> 'hora'));
      if v_valor is null then
        raise exception using errcode = '22023', message = 'parceiro_texto: valor fora da lista em quando';
      end if;
      v_texto := replace(v_texto, '{quando_fala}', v_valor);
      continue;
    end if;
    if v_campo in ('abertura', 'comigo') then
      if jsonb_typeof(d -> 'abertura') is distinct from 'string' then
        raise exception using errcode = '22023', message = 'parceiro_texto: falta abertura';
      end if;
      v_valor := d ->> 'abertura';
      if v_valor !~ c_abertura then
        raise exception using errcode = '22023', message = 'parceiro_texto: valor fora da lista em abertura';
      end if;
      -- O P01 só tem {comigo}: o {pessoa} ("Oi, Carla! ") é descartado, e o texto começa em "A partir de agora".
      if v_campo = 'comigo' and v_valor !~ 'assistente virtual da HBR\. $' then
        v_valor := '';
      end if;
      v_texto := replace(v_texto, '{' || v_campo || '}', v_valor);
      continue;
    end if;
    v_valor := btrim(d ->> v_campo);
    if coalesce(v_valor, '') = '' then
      raise exception using errcode = '22023', message = 'parceiro_texto: falta ' || v_campo;
    end if;
    v_ok := (case v_campo
      when 'nome' then char_length(v_valor) between 1 and 40 and v_valor !~ '[0-9]' and v_valor !~ '[[:cntrl:]{}]'
      when 'sigla' then v_valor ~ '^[A-Za-zÀ-ÖØ-öø-ÿ]{2,12}$'
      when 'bem' then v_valor = any (c_bens)
      when 'cliente' then v_valor ~ c_nome
      when 'primeiro_nome' then v_valor ~ c_nome
      when 'validade' then v_valor ~ '^[0-9]{2}/[0-9]{2}$'
      else false
    end);
    if not coalesce(v_ok, false) then
      raise exception using errcode = '22023', message = 'parceiro_texto: valor fora da lista em ' || v_campo;
    end if;
    v_texto := replace(v_texto, '{' || v_campo || '}', v_valor);
  end loop;

  -- ── O bloco P11 no P02: "Enquanto isso, o pátio de hoje:" e até 5 linhas prontas, com o mesmo "E mais" ──
  if p_tipo = 'parceiro_recibo' and v_variante = 'padrao'
     and jsonb_typeof(d -> 'bloco_linhas') = 'array' and jsonb_array_length(d -> 'bloco_linhas') > 0 then
    v_linhas := array(select x from jsonb_array_elements_text(d -> 'bloco_linhas') as x);
    if cardinality(v_linhas) > 5 or exists (select 1 from unnest(v_linhas) as l where l !~ c_linha) then
      raise exception using errcode = '22023', message = 'parceiro_texto: o bloco do pátio leva de 1 a 5 linhas no formato';
    end if;
    if d ? 'bloco_mais' then
      if coalesce(d ->> 'bloco_mais', '') !~ '^[0-9]{1,3}$' then
        raise exception using errcode = '22023', message = 'parceiro_texto: valor fora da lista em bloco_mais';
      end if;
      v_mais := (d ->> 'bloco_mais')::integer;
    end if;
    v_texto := v_texto || E'\nEnquanto isso, o pátio de hoje:\n' || array_to_string(v_linhas, E'\n');
    if v_mais > 0 then
      v_texto := v_texto || E'\n' || (case when v_mais = 1 then 'E mais 1 veículo.' else 'E mais ' || v_mais || ' veículos.' end);
    end if;
  end if;

  -- Falha fecha: espaço no começo ou dois espaços seguidos é montagem torta, e nada sai.
  if v_texto ~ '^[[:space:]]' or v_texto ~ '  ' then
    raise exception using errcode = '22023', message = 'parceiro_texto: espaço sobrando no texto';
  end if;
  return v_texto;
end;
$$;

comment on function public._parceiro_texto(text, text, jsonb) is
  'Retorno F4 (P4.1): o catálogo fixo da F4. Ao parceiro: P01–P16 e as linhas do painel e do pátio (variante linha); ao cliente final: Q01–Q05 (o papel do par decide) e Q03/Q03b. Falta de dado ou valor fora da lista = 22023. P04 e P15 saem sem o nome quando ele colide com nomes_de_outros.';

revoke all on function public._parceiro_texto(text, text, jsonb) from public, anon, authenticated;

-- ── 4. O contexto do validador do parceiro (C-VAL da F4) ────────────────────────────────────────────────────────────────

-- O contexto que a rodada passa ao validador real (validarSaidaAoParceiro, ou validarSaida nos Q ao cliente final). Lê de
-- p_dados: parceiro_id, pessoa_id, numero_id, interessado_ids, primeiro_nome, nome, quando e hora, dia, validade, datas,
-- linhas e bloco ([{service_order_id, estado, desde, rotulo, fora_por}]), marco e service_order_id (eco), abertura_id.
-- cliente_ouviu só é verdadeira quando _parceiro_cliente_ouviu (P7) não é nulo para CADA OS cuja linha afirma "avisado"
-- (as linhas pronto e o marco do eco); sem linha que afirme, fica falsa.
create or replace function public._parceiro_contexto_do_validador(p_saida uuid, p_texto text, p_dados jsonb, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_sep constant text := chr(31);
  c_dias constant text[] := array['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_agora timestamptz := coalesce(p_agora, now());
  v_s public.retorno_saidas;
  v_tipo text;
  v_texto text := coalesce(p_texto, '');
  v_fala text := public._retorno_quando_fala(d ->> 'quando', d ->> 'hora');
  v_parceiro uuid := nullif(d ->> 'parceiro_id', '')::uuid;
  v_pessoa uuid := nullif(d ->> 'pessoa_id', '')::uuid;
  v_numero uuid := nullif(d ->> 'numero_id', '')::uuid;
  v_abertura uuid;
  v_interessados uuid[];
  v_clientes uuid[];
  v_nomes jsonb;
  v_lista text[];
  v_datas text[] := '{}'::text[];
  v_cortar text[];
  v_trechos text[];
  v_corte text;
  v_valor text;
  v_papel text;
  v_marcos jsonb := '[]'::jsonb;
  v_ouviu boolean := false;
  v_cliente jsonb := '[]'::jsonb;
  v_dia date;
  r record;
begin
  select * into v_s from public.retorno_saidas s where s.id = p_saida;
  v_tipo := coalesce(v_s.tipo, d ->> 'tipo');

  -- Ao cliente final (Q01–Q05, Q03b): o validarSaida de hoje, sem outros nomes e com o nome do cliente permitido.
  if v_tipo in ('parceiro_aviso_cliente', 'parceiro_nao_mp_ok') then
    v_corte := v_texto;
    for v_valor in
      select x from unnest(array[d ->> 'nome']) as x where x is not null and btrim(x) <> '' order by char_length(x) desc, x
    loop
      v_corte := replace(v_corte, v_valor, c_sep);
    end loop;
    v_trechos := array(select p from unnest(string_to_array(v_corte, c_sep)) as p where btrim(p) <> '');
    return jsonb_build_object(
      'audiencia', 'cliente',
      'datas_permitidas', '[]'::jsonb,
      'horas_permitidas', '[]'::jsonb,
      'nome_permitido', nullif(btrim(d ->> 'nome'), ''),
      'nomes_de_outros', '[]'::jsonb,
      'os_permitidas', '[]'::jsonb,
      'textos_do_cliente', '[]'::jsonb,
      'trechos_do_modelo', to_jsonb(coalesce(v_trechos, '{}'::text[])),
      'marcas', jsonb_build_object('tem_proposta', false, 'tem_topo', false, 'cliente_ouviu', false, 'conferida', false));
  end if;

  -- Quem recebe: o parceiro e a pessoa do número, quando os dados não trazem.
  if v_numero is not null and (v_parceiro is null or v_pessoa is null) then
    select p.parceiro_id, n.pessoa_id into r
      from public.parceiro_numeros n
      join public.parceiro_pessoas p on p.id = n.pessoa_id
     where n.id = v_numero;
    if found then
      v_parceiro := coalesce(v_parceiro, r.parceiro_id);
      v_pessoa := coalesce(v_pessoa, r.pessoa_id);
    end if;
  end if;

  -- Os clientes citados, na ordem dos vínculos, e o papel comercial mais forte entre eles.
  v_interessados := array(select x::uuid
                            from jsonb_array_elements_text(case when jsonb_typeof(d -> 'interessado_ids') = 'array'
                                                                 then d -> 'interessado_ids' else '[]'::jsonb end) as x);
  v_clientes := array(select oi.client_id
                        from unnest(v_interessados) with ordinality as u(id, i)
                        join public.os_interessados oi on oi.id = u.id
                       order by u.i);
  select (case when bool_or(oi.papel = 'contratante') then 'contratante'
               when bool_or(oi.papel = 'pagador') then 'pagador'
               when bool_or(oi.papel = 'indicou') then 'indicou' end)
    into v_papel
    from public.os_interessados oi
   where oi.id = any (v_interessados);

  v_nomes := public._parceiro_nomes_do_contexto(v_parceiro, v_clientes, v_pessoa);
  v_lista := array(select jsonb_array_elements_text(v_nomes -> 'nomes_da_lista'));
  if nullif(btrim(d ->> 'primeiro_nome'), '') is not null then
    v_lista := v_lista || btrim(d ->> 'primeiro_nome');
  end if;

  -- As datas de cada linha (a desde, em dd/mm) e os marcos que afirmam "avisado".
  for r in
    select e.value as l from jsonb_array_elements(case when jsonb_typeof(d -> 'linhas') = 'array' then d -> 'linhas' else '[]'::jsonb end) e
    union all
    select e.value from jsonb_array_elements(case when jsonb_typeof(d -> 'bloco') = 'array' then d -> 'bloco' else '[]'::jsonb end) e
  loop
    if jsonb_typeof(r.l) = 'object' and r.l ->> 'fora_por' is null then
      if coalesce(r.l ->> 'desde', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        v_datas := v_datas || to_char((r.l ->> 'desde')::date, 'DD/MM');
      end if;
      if r.l ->> 'estado' = 'pronto' then
        v_marcos := v_marcos || jsonb_build_array(jsonb_build_object('os', r.l ->> 'service_order_id', 'marco', 'pronto'));
      end if;
    end if;
  end loop;
  if v_tipo = 'parceiro_eco' then
    v_marcos := v_marcos || jsonb_build_array(jsonb_build_object(
      'os', coalesce(d ->> 'service_order_id', d -> 'os_ids' ->> 0),
      'marco', coalesce(d ->> 'marco', v_s.variante)));
  end if;
  if jsonb_array_length(v_marcos) > 0 then
    select bool_and(public._parceiro_cliente_ouviu(nullif(m ->> 'os', '')::uuid, m ->> 'marco', v_agora) is not null)
      into v_ouviu
      from jsonb_array_elements(v_marcos) as m;
    v_ouviu := coalesce(v_ouviu, false);
  end if;

  -- As outras datas que o banco põe: o dia do cabeçalho ("ter (12/01)" e "12/01"), o prazo falado, a validade e a lista
  -- explícita.
  if coalesce(d ->> 'dia', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    v_dia := (d ->> 'dia')::date;
    v_datas := v_datas || (c_dias[extract(dow from v_dia)::integer + 1] || ' (' || to_char(v_dia, 'DD/MM') || ')')
                       || to_char(v_dia, 'DD/MM');
  end if;
  if v_fala is not null then
    v_datas := v_datas || v_fala;
  end if;
  if coalesce(d ->> 'validade', '') ~ '^[0-9]{2}/[0-9]{2}$' then
    v_datas := v_datas || (d ->> 'validade');
  end if;
  if jsonb_typeof(d -> 'datas') = 'array' then
    v_datas := v_datas || array(select jsonb_array_elements_text(d -> 'datas'));
  end if;
  v_datas := array(select distinct x from unnest(v_datas) as x where x is not null and btrim(x) <> '' order by x);

  -- Os trechos do modelo: o texto cortado nos nomes e nas datas (o maior primeiro). O bem, a sigla e o prazo falado são
  -- de listas fechadas e ficam no trecho.
  v_cortar := v_lista || v_datas || coalesce(array[v_nomes ->> 'nome_permitido'], '{}'::text[])
              || coalesce(array[nullif(btrim(d ->> 'nome'), '')], '{}'::text[]);
  v_corte := v_texto;
  for v_valor in
    select y.x from (select distinct x from unnest(v_cortar) as x where x is not null and btrim(x) <> '') y
     order by char_length(y.x) desc, y.x
  loop
    v_corte := replace(v_corte, v_valor, c_sep);
  end loop;
  v_trechos := array(select p from unnest(string_to_array(v_corte, c_sep)) as p where btrim(p) <> '');

  -- Os corpos das recebidas do caso, gravadas até agora (só para o eco; nunca entram no texto).
  v_abertura := coalesce(v_s.abertura_id, nullif(d ->> 'abertura_id', '')::uuid);
  if v_abertura is not null then
    select coalesce(jsonb_agg(w.body order by rm.recebida_em, rm.whatsapp_message_id), '[]'::jsonb) into v_cliente
      from public.retorno_mensagens rm
      join public.whatsapp_messages w on w.id = rm.whatsapp_message_id
     where rm.abertura_id = v_abertura
       and w.occurred_at <= v_agora
       and w.body is not null;
  end if;

  return jsonb_build_object(
    'audiencia', 'parceiro',
    'datas_permitidas', to_jsonb(v_datas),
    'horas_permitidas', '[]'::jsonb,
    'nome_permitido', v_nomes -> 'nome_permitido',
    'nomes_de_outros', coalesce(v_nomes -> 'nomes_de_outros', '[]'::jsonb),
    'nomes_da_lista', to_jsonb(v_lista),
    'papel_do_parceiro', v_papel,
    'os_permitidas', '[]'::jsonb,                      -- nenhum texto ao parceiro cita OS
    'textos_do_cliente', v_cliente,
    'trechos_do_modelo', to_jsonb(coalesce(v_trechos, '{}'::text[])),
    'marcas', jsonb_build_object('tem_proposta', false, 'tem_topo', false, 'cliente_ouviu', v_ouviu, 'conferida', false));
end;
$$;

comment on function public._parceiro_contexto_do_validador(uuid, text, jsonb, timestamptz) is
  'Retorno F4 (P4.2): o contexto do validador para uma saída da F4. Ao parceiro: datas das linhas, do cabeçalho, do prazo e da validade; nomes de _parceiro_nomes_do_contexto; papel mais forte dos vínculos citados; textos do caso (eco); trechos (o texto cortado nos nomes e datas); cliente_ouviu só quando cada linha pronto e o marco do eco foram ouvidos (_parceiro_cliente_ouviu, P7). Ao cliente final (Q): audiência cliente, sem outros nomes.';

revoke all on function public._parceiro_contexto_do_validador(uuid, text, jsonb, timestamptz) from public, anon, authenticated;

-- ── 5. Gerado do corpo vigente, com o trecho -- F4 ────────────────────────────────────────────────────────────────────

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
                    and s.enviada_em > j.desde and s.enviada_em < j.ate);
$$;
