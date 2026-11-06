-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), correção da revisão, Onda 4: o fecho da 3ª revisão, a última antes de publicar em teste.
-- Ordem de serviço: f7d/corr/decisoes-onda4.md (vale sobre a spec, o R6 e as notas). Achados: f7d/rev3/achados.md (A1, B1, B2, M1 a M10).
-- Notas: notas-fase7d.md, seção "Correção, Onda 4". Depende de 20261107100000 a 20261107100860. Vem antes da semente 20261107100900.
--
-- ═══ SÓ FUNÇÕES — OK NOMEADO ═══ (nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7d/corr4/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (a regra do "mais nova" é conferida na
-- montagem). Nas que vêm de antes da 7d (agenda_rascunho_planejar, _agenda_aplicar_planejar, agenda_desfazer, agenda_rascunho_desfazer), só blocos "-- FASE 7d: (correção …)" inseridos, ou a linha trocada
-- dentro de um bloco que já existia: tirados os blocos, é a origem, byte a byte. _agenda_desfazer_marco não muda, nem função de dinheiro, diária ou _agenda_vigia_*.
--
-- O QUE MUDA, por achado:
--   A1      a cidade da casa dita não sobrevive à frase seguinte: o lugar novo, o local do cadastro e o limpar zeram as 3 chaves; a casa não herda local_municipio; o *grava* só usa a cidade na linha da casa.
--   M5      a saída das recusas: "lugar novo: X" passa por cima de recado, data, estado e da pergunta do resolver. Continuam o vazio, as 60 letras e o cadastro vazio (T5). As 3 recusas e o "Qual deles"
--           sem "outro lugar em" dizem a saída.
--   M2      "São Paulo" e "Rio de Janeiro" são cidade: seguem como lugar novo, e a cidade vem de _agenda_municipio_conhecido. _agenda_uf_dita não muda.
--   M3      UF da base sem município conhecido não vai para a linha: "Cabeçudas, SC" é da região. UF de fora segue.
--   M4      frases inteiras que não são lugar: só com o texto inteiro igual.
--   M6      o "contém" do resolver: só locais de semente, o nome no começo, e nunca com "não" ou " ou ". _agenda_local_novo recusa "não" como recusa " ou ".
--   M7      _agenda_data_no_passado: " que " não corta depois da data; "foi dia" e "foi no dia", colados na data, são passado.
--   M8      o *grava* com local_id de linha inativa (outro ou casa_cliente) reativa, sob a trava de _agenda_local_criar. Linha ativa não toma trava nova.
--   M9      o *desfaz* do cancelar da vigia: depois do marco, se a OS segue concluída, o plano não volta, e o texto diz por quê.
--   M1      a releitura desse *desfaz* diz que a conclusão volta e a cobrança dela é cancelada.
--   M10     cidade de cliente "N/D", ".", "-" e vazia conta como sem cidade na casa do cliente; _agenda_municipio_conhecido tira a UF do candidato.
--
-- B1 (a trava do "1" com citação que não acha a fila) não tem banco: _shared/ai/whatsapp-channel.ts. O prompt e os papéis, idem. B2 é só papel.
--
-- SOMBRA: nada aqui está no caminho do motor, da vigia nem do fechamento em sombra (o M1, o M1c e o C8j seguem verdes). O que muda sem modo é conversa do dono: está na lista "entra sem modo" do roteiro.
--
-- PROVA: supabase/tests/agenda_fase7d_correcao4.sql.
--
-- DESFAZER: reaplicar as definições de 20261107100860 (_agenda_local_novo, _agenda_municipio_conhecido, agenda_resolver_local, _agenda_data_no_passado, agenda_desfazer, _agenda_aplicar_planejar,
-- agenda_rascunho_planejar), de 20261107100800 (_agenda_local_da_casa) e de 20261025100400 (agenda_rascunho_desfazer), e apagar _agenda_local_forcado.

-- ── A nova ─────────────────────────────────────────────────────────────────────────────────
-- (M5) A saída das recusas: o que vem depois de "lugar novo", com ou sem dois-pontos, em qualquer caixa, no começo do texto; nulo sem o prefixo. Sem nada depois, texto vazio: quem chama recusa.
create or replace function public._agenda_local_forcado(p_ref text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select btrim((regexp_match(coalesce(p_ref, ''), '^\s*lugar\s+novo(?:\s*:\s*|\s+|$)(.*)$', 'i'))[1]);
$function$;

comment on function public._agenda_local_forcado(text) is
  'Agenda de Produção (Fase 7d, correção M5): o texto depois de "lugar novo" ou "lugar novo:", no começo do que o dono disse; nulo sem o prefixo. Apoio de agenda_rascunho_planejar e _agenda_local_novo: é a saída de todas as recusas do lugar.';

-- ── As recriadas ───────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_local_novo(p_ref text)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  c_max       constant int := 60;       -- decisão do fio (O2): acima disso não é nome
  c_generico  constant text[] := array['cliente', 'ele', 'ela', 'dele', 'dela', 'casa', 'servico', 'bem', 'barco', 'motorhome', 'nao', 'sei', 'ninguem', 'nenhum', 'qualquer', 'algum', 'alguma',
                                        'outro', 'outra', 'cidade', 'mesmo', 'mesma', 'onde', 'ainda', 'sempre', 'residencia', 'endereco'];
  -- (correção G6, T8) recados, não lugares: só no começo do texto ou sozinhos ("Praia de Fora" passa)
  c_recado    constant text := '^(sim|ok|tanto faz|depois|a definir|a confirmar|vou ver|pergunta|talvez|acho|longe|perto|fora|por ai|de sempre|sempre|mesma|mesmo|seco|agua|garagem)( |$)';
  -- (correção M4) frases inteiras que não são nome de lugar: só com o texto INTEIRO igual, nunca "no começo" ("Essa Marina" e "Aguardando Cliente Ltda" passam)
  c_frases    constant text[] := array[
    'nenhum deles', 'nenhum desses', 'nenhum destes', 'nenhuma delas', 'nenhuma dessas', 'nenhuma destas', 'nenhum dos dois', 'nenhuma das duas', 'nenhum dos tres', 'nenhuma das tres',
    'nenhuma das opcoes', 'nenhuma dessas opcoes', 'nenhum desses lugares', 'nenhum desses locais',
    'outra marina', 'outro estaleiro', 'um outro lugar', 'um outro local', 'uma outra marina', 'outra opcao',
    'qualquer um', 'qualquer uma', 'qualquer um deles', 'qualquer uma delas',
    'o primeiro', 'a primeira', 'primeiro', 'primeira', 'o segundo', 'segundo', 'o terceiro', 'a terceira', 'terceiro', 'terceira', 'o ultimo', 'a ultima', 'ultimo', 'ultima',
    'a primeira opcao', 'a segunda opcao', 'a terceira opcao', 'a ultima opcao', 'primeira opcao', 'segunda opcao', 'terceira opcao', 'ultima opcao',
    'opcao 1', 'opcao 2', 'opcao 3', 'a opcao 1', 'a opcao 2', 'a opcao 3', 'opcao um', 'opcao dois', 'opcao tres',
    'a de cima', 'o de cima', 'a de baixo', 'o de baixo', 'cima', 'baixo',
    'esse', 'essa', 'este', 'esta', 'esse mesmo', 'essa mesma', 'esse ai', 'essa ai', 'esse aqui', 'essa aqui', 'este aqui', 'esta aqui',
    'aquele', 'aquela', 'aquele mesmo', 'aquela mesma', 'aquele ali', 'aquela ali', 'aquele la', 'aquela la', 'isso', 'isso mesmo', 'isso ai',
    'a combinar', 'combinar', 'vou combinar', 'vou confirmar', 'vou avisar', 'vou perguntar', 'vou descobrir', 'preciso ver', 'preciso confirmar', 'preciso perguntar', 'preciso saber', 'preciso descobrir',
    'a ver', 'vamos ver', 'a avisar', 'a decidir', 'a informar', 'a resolver', 'a saber', 'a verificar',
    'indefinido', 'indefinida', 'indeterminado', 'sem local', 'sem lugar', 'sem endereco', 'sem definicao', 'ainda sem local', 'ainda sem lugar', 'ainda indefinido',
    'ainda a definir', 'ainda a confirmar', 'ainda a combinar',
    'te falo', 'te digo', 'te aviso', 'te falo depois', 'te digo depois', 'te aviso depois', 'falo depois', 'digo depois', 'aviso depois', 'vejo depois', 'confirmo depois', 'confirmo',
    'eu confirmo', 'eu aviso', 'eu te aviso', 'eu te falo', 'eu te digo', 'ja te digo', 'ja te falo', 'ja te aviso',
    'aguardando', 'aguardando cliente', 'aguardando o cliente', 'aguardando confirmacao', 'aguardando retorno', 'esperando', 'esperando cliente', 'esperando o cliente', 'esperando confirmacao', 'esperando retorno',
    'o cliente vai dizer', 'o cliente vai confirmar', 'o cliente vai avisar', 'o cliente vai falar', 'o cliente diz', 'o cliente confirma', 'o cliente avisa', 'o cliente decide',
    'cliente vai dizer', 'cliente vai confirmar', 'cliente vai avisar', 'cliente diz', 'cliente confirma', 'cliente avisa', 'cliente decide',
    'ele vai me dizer', 'ele vai me avisar', 'ele vai me falar', 'ele vai dizer', 'ele vai avisar', 'ele vai confirmar', 'ele me avisa', 'ele me diz', 'ele me fala', 'ele avisa', 'ele diz', 'ele confirma',
    'ela vai me dizer', 'ela vai me avisar', 'ela vai me falar', 'ela vai dizer', 'ela vai avisar', 'ela vai confirmar', 'ela me avisa', 'ela me diz', 'ela me fala', 'ela avisa', 'ela diz', 'ela confirma',
    'onde estiver', 'onde ele estiver', 'onde ela estiver', 'onde o cliente estiver', 'onde der', 'onde for', 'onde quiser', 'onde ele quiser', 'onde ela quiser', 'onde o cliente quiser',
    'marina mesmo', 'oficina mesmo', 'estaleiro mesmo'];
  -- (correção M2) só estes 2 são estado e cidade de cliente: seguem como lugar novo, e a cidade vem de _agenda_municipio_conhecido. "na cidade de São Paulo" não muda
  c_cidade_estado constant text[] := array['sao paulo', 'rio de janeiro'];
  c_exemplo   constant text := 'me diga o nome do lugar (por exemplo, "Nova Trento").';
  c_saida     constant text := ' Se é mesmo um lugar, diga "lugar novo: %s".';   -- (correção M5) a saída das recusas: uma só, a mesma de "Qual deles" no rascunho
  v_forcado text := public._agenda_local_forcado(p_ref);   -- (correção M5) o que veio depois de "lugar novo:", ou nulo
  v_t    text := btrim(regexp_replace(coalesce(v_forcado, p_ref, ''), '\s+', ' ', 'g'));
  v_n    text;
  v_nome text;
  v_u    jsonb;   -- (correção G6) a UF dita no fim
begin
  -- O que veio junto do nome: "é em", "fica no", "outro lugar em"
  v_t := regexp_replace(v_t, '^((é|fica|ficou|está|tá|lá)\s+)*(outr[oa]\s+(lugar|local|ponto|endereço)\s+)?((em|no|na|nos|nas)\s+)?', '', 'i');
  v_t := btrim(regexp_replace(v_t, '[.,;:!?]+$', ''));
  v_n := public._agenda_normal(normalize(v_t, nfc));

  -- (correção M5) "lugar novo: X" passa por cima de recado, data e estado. Continuam o vazio, as 60 letras e, no rascunho, o cadastro vazio (T5)
  if v_forcado is not null and cardinality(public._agenda_local_palavras(v_t)) = 0 then
    return jsonb_build_object('ok', false, 'motivo', 'vazio', 'texto', 'Diga qual local: o nome da marina ou do estaleiro, ou "pátio".');
  end if;
  if v_forcado is null and v_n !~ '[a-z]{2}' then
    if v_n ~ '\d' then
      return jsonb_build_object('ok', false, 'motivo', 'data', 'texto', format('"%s" não é um lugar: %s', btrim(p_ref), c_exemplo));
    end if;
    return jsonb_build_object('ok', false, 'motivo', 'vazio', 'texto', 'Diga qual local: o nome da marina ou do estaleiro, ou "pátio".');
  end if;
  if v_forcado is null
     and (public._agenda_preparar_data(v_t) ~ '\mdia \d{1,2}\M' or v_n ~ '\m\d{1,2}/\d{1,2}'
          or v_n ~ '\m(segunda|terca|quarta|quinta|sexta|sabado|domingo|amanha|hoje|ontem|semana|mes)\M') then
    return jsonb_build_object('ok', false, 'motivo', 'data', 'texto', format('"%s" parece uma data, não um lugar: %s', btrim(p_ref), c_exemplo) || format(c_saida, btrim(p_ref)));
  end if;
  if char_length(v_t) > c_max then
    return jsonb_build_object('ok', false, 'motivo', 'longo', 'texto', format('Esse nome passa de %s letras: %s', c_max, c_exemplo));
  end if;
  -- (correção G6) o estado inteiro não é um lugar; a UF no fim sai do nome ("Nova Trento, SC" é Nova Trento, em SC)
  if v_forcado is null and v_n <> all (c_cidade_estado) and public._agenda_uf_dita(v_t) is not null then
    return jsonb_build_object('ok', false, 'motivo', 'estado', 'texto', format('"%s" é um estado: me diga a cidade ou o nome do lugar.', v_t) || format(c_saida, btrim(p_ref)));
  end if;
  v_u := public._agenda_local_sem_uf(v_t);
  v_t := v_u ->> 'texto';
  v_n := public._agenda_normal(normalize(v_t, nfc));
  -- ("Itajaí ou Navegantes" é dúvida: 2 lugares não são um nome) (correção M6) "não é na Kalmar" também: quem nega não está dando o nome
  if v_forcado is null
     and (v_n ~ c_recado or v_n = any (c_frases) or v_n ~ ' ou ' or v_n ~ '\mnao\M'
          or not exists (select 1 from unnest(public._agenda_local_palavras(v_t)) w where w <> all (c_generico))) then
    return jsonb_build_object('ok', false, 'motivo', 'vazio', 'texto', format('Não entendi o lugar: %s', c_exemplo) || format(c_saida, btrim(p_ref)));
  end if;

  -- (correção G6) "outro lugar em BC": a cidade pelo nome dela
  if v_n in ('balneario', 'bc') then
    v_t := 'Balneário Camboriú';
  end if;
  -- A caixa: a 1ª de cada palavra, "de" e "do" em minúscula, a sigla como veio. Tudo em maiúscula é grito, não sigla.
  v_nome := array_to_string(array(
    select case when o > 1 and lower(w) = any (array['de', 'do', 'da', 'dos', 'das', 'e', 'em']) then lower(w)
                when w = upper(w) and w <> lower(w) and char_length(w) <= 3 and v_t <> upper(v_t) then w
                else public._agenda_maiuscula(lower(w)) end
      from unnest(string_to_array(v_t, ' ')) with ordinality u(w, o) order by o), ' ');
  return jsonb_build_object('ok', true, 'nome', v_nome, 'uf', v_u ->> 'uf');
end;
$function$;

create or replace function public._agenda_municipio_conhecido(p_nome text, p_os uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_cand   text[];
  v_n      text;
  v_mun    text;
  v_uf     text;
  v_mun2   text;   -- (correção T10) os outros clientes
  v_uf2    text;
begin
  v_cand := array_remove(array[p_nome, (regexp_match(p_nome, '\sem\s+(.+)$', 'i'))[1]], null);
  foreach v_n in array v_cand loop
    -- (correção M10) a UF no fim não é parte da cidade ("Bombinhas, SC")
    v_n := public._agenda_normal(normalize(public._agenda_local_sem_uf(v_n) ->> 'texto', nfc));
    -- o cliente da OS
    select btrim(cl.city), upper(btrim(coalesce(cl.state, ''))) into v_mun, v_uf
      from public.service_orders so join public.clients cl on cl.id = so.client_id
     where so.id = p_os and position(chr(65533) in coalesce(cl.city, '')) = 0
       and public._agenda_normal(normalize(coalesce(cl.city, ''), nfc)) = v_n;
    -- os locais do cadastro
    if v_mun is null then
      select l.municipio, l.uf into v_mun, v_uf from public.agenda_locais l
       where l.ativo and l.municipio is not null and public._agenda_normal(normalize(l.municipio, nfc)) = v_n
       order by l.uf nulls last, l.municipio limit 1;
    end if;
    -- a região
    if v_mun is null then
      select m into v_mun from unnest(c.municipios_locais) m where public._agenda_normal(normalize(m, nfc)) = v_n limit 1;
    end if;
    -- os outros clientes: a grafia e a UF mais comuns
    if v_mun is null or nullif(v_uf, '') is null then
      select x.cidade, x.uf into v_mun2, v_uf2
        from (select btrim(cl.city) as cidade, upper(btrim(coalesce(cl.state, ''))) as uf, count(*) as n
                from public.clients cl
               where cl.city is not null and position(chr(65533) in cl.city) = 0
                 and public._agenda_normal(normalize(cl.city, nfc)) = v_n
               group by 1, 2
               order by (upper(btrim(coalesce(cl.state, ''))) ~ '^[A-Z]{2}$') desc, count(*) desc, 1, 2
               limit 1) x;
      -- (correção T10) sem cliente nessa cidade, o que a região achou fica
      if found then
        v_mun := coalesce(v_mun, v_mun2);
        v_uf := v_uf2;
      end if;
    end if;
    if v_mun is not null and char_length(v_mun) between 2 and 60 then
      return jsonb_build_object('municipio', v_mun, 'uf', case when v_uf ~ '^[A-Z]{2}$' then v_uf end);
    end if;
    v_mun := null;
    v_uf := null;
  end loop;
  return jsonb_build_object('municipio', null, 'uf', null);
end;
$function$;

create or replace function public._agenda_local_da_casa(p_os uuid, p_autor uuid)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cl   record;
  l    public.agenda_locais;
  v_id uuid;
  v_mun text;
  v_uf  text;
  v_nome text;
begin
  select c.id, c.name, c.city, c.state into cl
    from public.service_orders so join public.clients c on c.id = so.client_id where so.id = p_os;
  if cl.id is null then
    raise exception 'o serviço não tem cliente: não sei de quem é a casa' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('agenda_local_criar'));
  select * into l from public.agenda_locais x where x.tipo = 'casa_cliente' and x.client_id = cl.id;
  if l.id is not null then
    if l.ativo then
      return jsonb_build_object('id', l.id, 'nome', l.nome, 'criada', false);
    end if;
    update public.agenda_locais x set ativo = true, atualizado_por = p_autor where x.id = l.id;
    return jsonb_build_object('id', l.id, 'nome', l.nome, 'criada', true);
  end if;
  v_mun := nullif(btrim(coalesce(cl.city, '')), '');
  -- (correção M10) "N/D" não é cidade ("." e "-" já não passam pelo tamanho)
  v_mun := case when char_length(v_mun) between 2 and 60 and position(chr(65533) in v_mun) = 0 and upper(v_mun) <> 'N/D' then v_mun end;
  v_uf := upper(btrim(coalesce(cl.state, '')));
  v_uf := case when v_uf ~ '^[A-Z]{2}$' and v_mun is not null then v_uf end;
  v_nome := left('casa de ' || public._agenda_nome_curto(cl.name), 80);
  insert into public.agenda_locais (nome, tipo, municipio, uf, client_id, atualizado_por)
  values (v_nome, 'casa_cliente', v_mun, v_uf, cl.id, p_autor)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'nome', v_nome, 'criada', true);
end;
$function$;

create or replace function public.agenda_resolver_local(p_ref text, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_patio   constant text[] := array['patio', 'oficina', 'hbr'];   -- §5.7: as palavras do local patio_hbr; valem mesmo se os apelidos mudarem
  c_prefixo constant int := 3;   -- estrutural: abaixo disso, só a palavra inteira ("mp")
  c_lista   constant int := 6;   -- §5.7: nao_achei lista até 6 locais ativos
  v_ref     text := btrim(coalesce(p_ref, ''));
  -- (correção G6) a UF no fim não é parte do nome, e "Balneário" e "BC" são a cidade de Balneário Camboriú: seguem o caminho da cidade
  v_toks    text := regexp_replace(array_to_string(public._agenda_local_palavras(public._agenda_local_sem_uf(p_ref) ->> 'texto'), ' '),
                                   '\m(bc|balneario(?! camboriu))\M', 'balneario camboriu', 'g');
  v_tok     text[] := string_to_array(v_toks, ' ');
  v_c       jsonb;
  v_todos   boolean;
  v_achados jsonb;
  v_n       int;
  v_op      text[];
  v_nomes   text[];
  v_cidade  text;   -- (correção O2) a cidade dita, quando ela tem locais: a saída "outro lugar em {cidade}"
begin
  if v_toks = '' then
    return jsonb_build_object('status', 'nao_achei', 'id', null, 'nome', null, 'opcoes', '[]'::jsonb,
      'texto', 'Diga qual local: o nome da marina ou do estaleiro, ou "pátio".');
  end if;
  if v_toks ~ '^casa (cliente|dele|dela)( |$)' then
    return jsonb_build_object('status', 'casa_cliente', 'id', null, 'nome', null, 'opcoes', '[]'::jsonb, 'texto', 'na casa do cliente');
  end if;

  -- Por local: o que sobra do que o dono disse, tirada a cidade do local ("Kalmar em Itajaí"), e quantas dessas palavras o nome e os apelidos explicam.
  with l as (
    select x.id, x.nome, x.municipio, public._agenda_normal(normalize(x.nome, nfc)) as ordem,
           array_to_string(public._agenda_local_palavras(x.municipio), ' ') as cidade,
           public._agenda_local_palavras(x.nome) || public._agenda_local_palavras(array_to_string(x.apelidos, ' '))
           || case when x.tipo = 'patio_hbr' then c_patio else '{}'::text[] end as palavras,
           -- (correção G6) os nomes inteiros: o nome, os apelidos e a sigla do começo do nome ("MP"). "pátio" e "oficina" sozinhos não: "na oficina do João" é outro lugar. A linha com o nome da cidade
           -- também não: "Marina do João em Nova Trento" não é a linha "Nova Trento"
           -- (correção M6) só os locais de semente: a linha que o dono criou ("Centro", "Porto") só casa pelas regras de sempre
           array(select array_to_string(public._agenda_local_palavras(i), ' ')
                   from unnest(x.apelidos || x.nome || (regexp_match(x.nome, '^([A-Z]{2,5})\s'))[1]) i
                  where x.tipo <> 'outro' and i is not null and public._agenda_normal(normalize(i, nfc)) <> all (array['patio', 'oficina'])
                    and public._agenda_normal(normalize(x.nome, nfc)) is distinct from public._agenda_normal(normalize(x.municipio, nfc))) as inteiros
      from public.agenda_locais x
     where x.ativo and x.tipo <> 'casa_cliente'   -- (correção O3) a casa é de um cliente: nunca é o local de outro
  ),
  t as (
    select l.*, string_to_array(btrim(replace(' ' || v_toks || ' ', ' ' || l.cidade || ' ', ' ')), ' ') as resto
      from l
  ),
  c as (
    select t.*,
           (select count(*) from unnest(t.resto) r
             where exists (select 1 from unnest(t.palavras) w where w = r or (char_length(r) >= c_prefixo and w like r || '%')))::int as cobre,
           (select count(*) from unnest(t.resto) r where r = any (t.palavras))::int as exatas,
           exists (select 1 from unnest(t.inteiros) i where i <> '' and (regexp_replace(v_toks, '^((garagem|vaga|pier|box|\d+) )+', '') || ' ') like (i || ' %')) as contem,
           array(select k from unnest(v_tok) k
                  where exists (select 1 from unnest(t.palavras) w where w = k or (char_length(k) >= c_prefixo and w like k || '%'))) as dele
      from t
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'municipio', c.municipio, 'so_cidade', v_toks = c.cidade,
                                               'tudo', cardinality(c.resto) > 0 and c.cobre = cardinality(c.resto),
                                               'exato', cardinality(c.resto) > 0 and c.exatas = cardinality(c.resto),
                                               'contem', c.contem, 'parte', cardinality(c.dele) > 0) order by c.ordem, c.id), '[]'::jsonb),
         not exists (select 1 from unnest(v_tok) k where not exists (select 1 from c c2 where k = any (c2.dele))),
         array_agg(c.nome order by c.ordem, c.id)
    into v_c, v_todos, v_nomes
    from c;

  -- O nome inteiro vence o "começa com"
  select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_achados from jsonb_array_elements(v_c) with ordinality u(e, o)
   where (e ->> 'tudo')::boolean and (e ->> 'exato')::boolean;
  if jsonb_array_length(v_achados) = 0 then
    select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_achados from jsonb_array_elements(v_c) with ordinality u(e, o)
     where (e ->> 'tudo')::boolean;
  end if;
  -- (correção G6) o texto contém o nome inteiro de um local: é ele ("Marina Itajaí em seco", "garagem da Marina Itajaí"); com 2 nomes, a pergunta de sempre. "pátio da Kalmar" não: cada palavra é de um
  -- local, e nunca escolho sozinho (abaixo)
  -- (correção M6) o nome tem de vir no começo; com "não" ou " ou " no texto ele não vale: "não é na Kalmar" e "Marina Itajaí ou Penha" não são esses locais
  if jsonb_array_length(v_achados) = 0 and not v_todos and v_toks !~ '\mnao\M' and v_toks !~ ' ou ' then
    select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_achados from jsonb_array_elements(v_c) with ordinality u(e, o)
     where (e ->> 'contem')::boolean;
  end if;
  -- Só a cidade: mais de um local nela é pergunta; um só não identifica ("Penha" pode ser a casa do cliente)
  if jsonb_array_length(v_achados) = 0 then
    select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_achados from jsonb_array_elements(v_c) with ordinality u(e, o)
     where (e ->> 'so_cidade')::boolean;
    -- (correção O2) a cidade com local cadastrado pergunta qual, com a saída; a de 1 local também: "Penha" pode ser a casa do cliente, e agora o dono tem como dizer
    -- o lugar novo que tem o nome da cidade ("Nova Trento", sozinho nela) é ele mesmo: não há o que perguntar
    if jsonb_array_length(v_achados) > 0
       and not (jsonb_array_length(v_achados) = 1 and public._agenda_normal(normalize(v_achados -> 0 ->> 'nome', nfc)) = public._agenda_normal(normalize(v_achados -> 0 ->> 'municipio', nfc))) then
      v_cidade := v_achados -> 0 ->> 'municipio';
    end if;
  end if;
  -- Cada palavra é de um local, mas nenhum explica todas ("pátio da Kalmar"): nunca escolho o pátio sozinho
  if jsonb_array_length(v_achados) = 0 and v_todos then
    select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_achados from jsonb_array_elements(v_c) with ordinality u(e, o)
     where (e ->> 'parte')::boolean;
  end if;

  v_n := jsonb_array_length(v_achados);
  if v_n = 0 then
    return jsonb_build_object('status', 'nao_achei', 'id', null, 'nome', null, 'opcoes', '[]'::jsonb,
      'texto', format('Não achei "%s" no cadastro.', v_ref)
               || case when cardinality(v_nomes) > 0 then format(' Os locais que tenho: %s.', public._agenda_lista(v_nomes, c_lista)) else '' end);
  end if;
  if v_n = 1 and v_cidade is null then
    return jsonb_build_object('status', 'ok', 'id', v_achados -> 0 ->> 'id', 'nome', v_achados -> 0 ->> 'nome', 'opcoes', '[]'::jsonb,
      'texto', public._agenda_local_no(v_achados -> 0 ->> 'nome'));
  end if;
  -- (correção O2) o lugar novo pode não ter município
  v_op := array(select concat(e ->> 'nome', ' (' || (e ->> 'municipio') || ')') from jsonb_array_elements(v_achados) with ordinality u(e, o) order by o);
  if v_cidade is not null then
    v_op := v_op || format('outro lugar em %s', v_cidade);
  end if;
  return jsonb_build_object('status', 'ambiguo', 'id', null, 'nome', null,
    'opcoes', (select jsonb_agg(jsonb_build_object('id', e ->> 'id', 'nome', e ->> 'nome', 'municipio', e ->> 'municipio') order by o)
                 from jsonb_array_elements(v_achados) with ordinality u(e, o)),
    'texto', format('Qual deles: %s ou %s?', array_to_string(v_op[1:cardinality(v_op) - 1], ', '), v_op[cardinality(v_op)]));
end;
$function$;

create or replace function public._agenda_data_no_passado(p_trecho text, p_dito text, p_lado text)
 returns boolean
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  c_chega constant text := '\m(chegou|chegaram|entrou|veio|trouxe|deixou|ja esta|desde|apareceu|entregaram)\M';
  c_sai   constant text := '\m(saiu|buscou|levou|retirou|foi embora)\M';
  v_t text := ' ' || public._agenda_preparar_data(regexp_replace(coalesce(p_trecho, ''), '[,;]', ' e ', 'g')) || ' ';
  v_d text := ' ' || public._agenda_preparar_data(p_dito) || ' ';
  v_i int := position(v_d in v_t);
  v_o text;
  v_a text;   -- (correção M7) o que vem antes da data, na oração dela
begin
  if v_i = 0 then
    return false;
  end if;
  -- (correção M7) " que " só corta antes da data: "foi dia 5 que chegou" é passado, e o verbo vem depois. "foi dia" e "foi no dia", colados na data, são passado nos 2 lados; "foi" solto não ("foi marcado para dia 20")
  v_a := regexp_replace(left(v_t, v_i), '^.* (que|e|mas) ', ' ');
  v_o := v_a || btrim(v_d) || regexp_replace(substr(v_t, v_i + char_length(v_d) - 1), ' (e|mas) .*$', ' ');
  return v_o !~ '\mnao\M' and (v_o ~ case when p_lado = 'sai' then c_sai else c_chega end or (v_a || btrim(v_d)) ~ ' foi( no)? dia \d');
end;
$function$;

create or replace function public.agenda_desfazer(p_acao uuid, p_autor uuid default null, p_via text default 'dono',
                                                  p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_a     public.agenda_acoes%rowtype;
  v_nome  text;
  v_x     record;
  v_novas uuid[] := '{}';
  v_canc  uuid[] := '{}';
  v_id    uuid;
  v_os    uuid;
  v_acao  uuid;
  v_txt   text;
  v_q     public.agenda_perguntas%rowtype;
  v_dias  date[];
  -- FASE 7: (7a P7) os ramos das ações do gestor (estimar, dupla, gestor) e quem saiu da equipe
  v_f7_pl    public.os_planejamento%rowtype;
  v_f7_txt   text;
  v_f7_acao  uuid;
  v_f7_sai   uuid[] := '{}';
  v_f7_fora  uuid[] := '{}';
  v_f7_ficam int := 0;
  v_f7_nomes text;
  -- FASE 7: fim
  -- FASE 7b: (7b P3) quem entrou na rotina da equipe sai
  v_7b_acao uuid;
  v_7b_txt  text;
  v_7b_nome text;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achado 18) desfazer a 2ª pessoa da dupla
  v_7bc_ajud text;
  -- FASE 7b: fim
  -- FASE 7d: (correção G5) a entrega que o cancelar da vigia seguiu
  v_7d_marco uuid;
  v_7d_rm    jsonb;
  -- FASE 7d: fim
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found then
    raise exception 'Não encontrei essa mudança.' using errcode = 'P0002';
  end if;
  v_os := v_a.service_order_id;
  v_nome := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                        join public.clients cl on cl.id = so.client_id where so.id = v_os), 'serviço');
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste da agenda automática: nada mudou para desfazer.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.tipo = 'desfazer' then
    return jsonb_build_object('ok', false, 'texto', 'Não desfaço um desfazer: me diga o dia que você quer.');
  end if;
  -- FASE 3: a conclusão e a entrega têm o desfazer delas (o status e a saída pela porta, as cobranças da conclusão, a
  -- comissão de vendedor, os vencimentos "na entrega" e a entrega): _agenda_desfazer_marco (20261026100100).
  if v_a.tipo in ('concluir', 'entregar') then
    return public._agenda_desfazer_marco(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 3 (P4): a diária que a agenda lançou: apaga o turno que ela criou, se o acerto está aberto (_agenda_desfazer_diaria).
  if v_a.tipo = 'diaria' then
    return public._agenda_desfazer_diaria(v_a.id, p_autor, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 4: a mudança do material que o gestor fez sozinho (a previsão pela mensagem do fornecedor, a chegada pela nota
  -- importada): as linhas voltam como estavam, se ninguém mexeu nelas depois (_agenda_desfazer_material, 20261027100400).
  if v_a.tipo = 'material' then
    return public._agenda_desfazer_material(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 4: fim
  -- FASE 5: o que a resposta do cliente mudou (a confirmação, o pedido de dia, o acesso: a ação com depois.resposta_id) tem
  -- o desfazer dela (_agenda_desfazer_cliente, 20261028100400); a mensagem enviada não se desmanda; o acorde e a decisão do
  -- aviso crítico não mudaram nada na agenda.
  if v_a.origem = 'cliente' and v_a.tipo in ('fixar', 'cliente') and v_a.depois ? 'resposta_id' then
    return public._agenda_desfazer_cliente(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  if v_a.tipo = 'cliente' then
    return jsonb_build_object('ok', false,
      'texto', case when v_a.depois ? 'mensagem_id' then 'Mensagem enviada não se desmanda.'
                    else 'Isso foi um aviso para você: nada mudou na agenda para desfazer.' end);
  end if;
  -- FASE 5: fim
  -- FASE 6: (P6) o que o aprendizado mudou (a troca que entrou sozinha e a decisão 1 ou 3 do dono) tem o desfazer dele: o
  -- valor de antes volta e a chave fica travada; a carga volta carga_max (_agenda_desfazer_aprendizado, 20261029100600).
  if v_a.tipo = 'aprendizado' then
    return public._agenda_desfazer_aprendizado(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 6: fim
  -- FASE 7d: (7d P5, §5.5) a ação local tem o desfazer dela: as colunas de os_planejamento voltam ao antes, as linhas de os_autorizados que ela criou
  -- ganham revogado_em e o replano do "Segure o dia" volta (_agenda_desfazer_local)
  if v_a.tipo = 'local' then
    return public._agenda_desfazer_local(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 7d: fim
  -- FASE 7: (7a P7, spec R3 e §5.7) as ações do gestor que não são de alocação têm o ramo delas: estimar (os dias que o gestor
  -- gravou pelo prazo ou pela opção 1: os_planejamento.dias, estimativa_fonte e estimativa_em voltam ao antes da ação), dupla
  -- (dupla_dita, dupla_meios, dupla_motivo e dupla_em voltam) e gestor (*gestor, só propor* / *pode marcar*: gestor_so_propor e
  -- gestor_so_propor_em voltam). Só se nada mudou depois da ação (o que está gravado é o depois dela); senão a recusa diz o que
  -- mudou. reparar e reestimar são de alocação e seguem o caminho de sempre.
  if v_a.tipo in ('estimar', 'dupla', 'gestor') then
    if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
      return jsonb_build_object('ok', false,
        'texto', case when v_a.tipo = 'gestor' then 'Não dá mais para desfazer: passou o prazo. Diga *gestor, só propor* ou *gestor, pode marcar*.'
                      else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga.', v_nome) end);
    end if;
    if v_a.tipo = 'gestor' then
      if (select c.gestor_so_propor from public.agenda_config c where c.id)
         is distinct from (v_a.depois ->> 'gestor_so_propor')::boolean then
        return jsonb_build_object('ok', false,
          'texto', 'Não desfaço: depois disso você já mudou o gestor de novo. Diga *gestor, só propor* ou *gestor, pode marcar*.');
      end if;
      update public.agenda_config
         set gestor_so_propor = coalesce((v_a.antes ->> 'gestor_so_propor')::boolean, false),
             gestor_so_propor_em = (v_a.antes ->> 'gestor_so_propor_em')::timestamptz,
             atualizado_em = p_agora, atualizado_por = p_autor
       where id;
      v_f7_txt := case when coalesce((v_a.antes ->> 'gestor_so_propor')::boolean, false)
                       then 'Desfeito: voltei a só sugerir. *gestor, pode marcar* volta a marcar.'
                       else 'Desfeito: voltei a marcar sozinho; o que eu marcar vem no seu fechamento, com *desfaz*.' end;
    else
      select * into v_f7_pl from public.os_planejamento where service_order_id = v_os for update;
      if not found then
        return jsonb_build_object('ok', false, 'texto', format('Não achei o planejamento do %s: nada mudou.', v_nome));
      end if;
      if v_a.tipo = 'estimar' then
        if v_f7_pl.dias is distinct from (v_a.depois ->> 'dias')::numeric or v_f7_pl.estimativa_fonte is distinct from 'orcamento' then
          return jsonb_build_object('ok', false,
            'texto', format('Não desfaço: depois disso os dias do %s mudaram (%s). Para mudar de novo, me diga os dias.', v_nome,
                            coalesce(public._agenda_dias(v_f7_pl.dias), 'sem dias')));
        end if;
        update public.os_planejamento
           set dias = (v_a.antes ->> 'dias')::numeric, estimativa_fonte = v_a.antes ->> 'estimativa_fonte',
               estimativa_em = (v_a.antes ->> 'estimativa_em')::timestamptz,
               historico = public._os_material_historico(v_f7_pl.historico, jsonb_build_object(
                 'em', p_hoje, 'quando', p_agora, 'autor', p_autor, 'por', 'dono', 'motivo', 'desfeito', 'acao', v_a.id,
                 'antes', v_a.depois, 'depois', v_a.antes)),
               atualizado_em = p_agora, atualizado_por = p_autor
         where service_order_id = v_os;
        v_f7_txt := case when v_a.antes ->> 'dias' is null
                         then format('Desfeito: o %s volta sem os dias que eu contei (%s). Me diga quantos dias são.',
                                     public._agenda_rotulo_da_os(v_os), public._agenda_dias((v_a.depois ->> 'dias')::numeric))
                         else format('Desfeito: o %s volta a %s, como estava.', public._agenda_rotulo_da_os(v_os),
                                     public._agenda_dias((v_a.antes ->> 'dias')::numeric)) end;
      else
        if v_f7_pl.dupla_dita is distinct from v_a.depois ->> 'dupla_dita'
           or v_f7_pl.dupla_meios is distinct from (v_a.depois ->> 'dupla_meios')::smallint then
          return jsonb_build_object('ok', false,
            'texto', format('Não desfaço: depois disso a dupla do %s mudou. Diga *%s com dupla* ou *%s sem dupla*.', v_nome, v_nome, v_nome));
        end if;
        update public.os_planejamento
           set dupla_dita = v_a.antes ->> 'dupla_dita', dupla_meios = (v_a.antes ->> 'dupla_meios')::smallint,
               dupla_motivo = v_a.antes ->> 'dupla_motivo', dupla_em = (v_a.antes ->> 'dupla_em')::timestamptz,
               historico = public._os_material_historico(v_f7_pl.historico, jsonb_build_object(
                 'em', p_agora, 'autor', p_autor, 'por', 'dono', 'trecho', 'desfeito', 'acao', v_a.id,
                 'antes', v_a.depois, 'depois', v_a.antes)),
               atualizado_em = p_agora, atualizado_por = p_autor
         where service_order_id = v_os;
        v_f7_txt := format('Desfeito: o %s volta %s.', public._agenda_rotulo_da_os(v_os),
                           case v_a.antes ->> 'dupla_dita'
                             when 'todos' then 'com dupla'
                             when 'nao' then 'sem dupla'
                             when 'inicio' then 'com dupla no início'
                             when 'fim' then 'com dupla no fim'
                             else 'ao normal: 1 pessoa, e dupla só quando você marcar' end);
      end if;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto,
                                     autor, desfaz_a)
    values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
            v_a.os_ids, false, jsonb_build_object('acao', v_a.id), v_a.antes, left(v_f7_txt, 400), p_autor, v_a.id)
    returning id into v_f7_acao;
    update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_f7_acao where id = v_a.id;
    return jsonb_build_object('ok', true, 'texto', v_f7_txt, 'acao_id', v_f7_acao, 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb);
  end if;
  -- FASE 7: fim
  -- FASE 7b: (7b P3, §5.2) a entrada na rotina da equipe — a ação equipe da regra d14 (vigia) ou do "1) Ponho" do dono (depois.motivo
  -- regra_d14 ou contato) — sai: recebe_rotina false e a linha parada ("desfeito pelo dono"); a regra não a põe de novo (a linha existe).
  if v_a.tipo = 'equipe' and v_a.depois ->> 'motivo' in ('regra_d14', 'contato') then
    v_7b_nome := coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_a.payee_id), 'a pessoa');
    if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
      return jsonb_build_object('ok', false,
        'texto', format('Não dá mais para desfazer: passou o prazo. Se quiser tirar %s da rotina da equipe, me diga.', v_7b_nome));
    end if;
    update public.agenda_equipe_contato
       set recebe_rotina = false, parou_em = p_agora, parou_motivo = 'desfeito pelo dono'
     where payee_id = v_a.payee_id and parou_em is null;
    if not found then
      return jsonb_build_object('ok', false, 'texto', format('%s já não está na rotina da equipe: nada mudou.', v_7b_nome));
    end if;
    v_7b_txt := format('Desfeito: %s sai da rotina da equipe e não recebe mais a ficha nem a pergunta dos dias.', v_7b_nome);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, payee_id, os_ids, critica, antes, depois, texto, autor,
                                     desfaz_a)
    values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer',
            v_a.payee_id, '{}'::uuid[], false, jsonb_build_object('acao', v_a.id), jsonb_build_object('recebe_rotina', false),
            left(v_7b_txt, 400), p_autor, v_a.id)
    returning id into v_7b_acao;
    update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_7b_acao where id = v_a.id;
    return jsonb_build_object('ok', true, 'texto', v_7b_txt, 'acao_id', v_7b_acao, 'recriadas', '[]'::jsonb,
                              'canceladas', '[]'::jsonb);
  end if;
  -- FASE 7b: fim
  if v_a.desfazivel_ate is null then
    return jsonb_build_object('ok', false, 'texto', 'Essa mudança foi pedida por você: para mudar de novo, me diga o dia.');
  end if;
  if p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false,
      'texto', case when exists (select 1 from public.agenda_alocacoes a where a.id = any (v_a.alocacoes_criadas)
                                                                       and lower(a.periodo) <= p_agora)
                    then format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome)
                    else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga o dia.', v_nome) end);
  end if;
  if exists (select 1 from public.agenda_alocacoes a
              where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')
                and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome));
  end if;
  -- recriar o que saiu não pode bater em quem já está no lugar
  select a.dia, a.turno, py.name as pessoa, cl.name as cliente into v_x
    from public.agenda_alocacoes c
    join public.agenda_alocacoes a on a.payee_id = c.payee_id and a.periodo && c.periodo and a.estado in ('publicada', 'fixada')
                                  and not (a.id = any (v_a.alocacoes_criadas))
    join public.payees py on py.id = a.payee_id
    join public.service_orders so on so.id = a.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
   order by a.dia, a.turno = 'tarde'
   limit 1;
  if found then
    -- FASE 7b: (correção da revisão da 7b, achado 18) no serviço em que o gestor completou a dupla, a revisão encurtou o fim e outra OS
    -- ocupou o meio-dia que sobrou: a recusa (a regra de sempre: o *desfaz* nunca sobrepõe) diz como voltar — desfazer antes o que
    -- ocupou o lugar
    if v_os is not null and exists (select 1 from public.agenda_alocacoes a
                                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.motivos ? 'dupla_completa') then
      v_7bc_ajud := public._agenda_lista(array(
                      select distinct public._agenda_nome_curto(py.name) from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                       where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.motivos ? 'dupla_completa' order by 1));
      return jsonb_build_object('ok', false,
        'texto', format('Não dá para desfazer: o %s já está no %s %s. Com %s junto, o %s acaba antes; se quiser o dia de volta mesmo assim, diga *desfaz %s* e depois *desfaz %s*.',
                        public._agenda_nome_curto(v_x.pessoa), coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'),
                        public._agenda_meio_texto(v_x.dia, v_x.turno), v_7bc_ajud, v_nome,
                        coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), v_nome));
    end if;
    -- FASE 7b: fim
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: o %s já está no %s %s.', public._agenda_nome_curto(v_x.pessoa),
                      coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), public._agenda_meio_texto(v_x.dia, v_x.turno)));
  end if;

  -- FASE 7: (7a P7; fase7-padroes "medição de 30/10", item 4) o que a ação tirou e era de quem não está mais na equipe (a
  -- grade, agenda_capacidade, naquele dia) não volta: o *desfaz* restaura só o que cabe e diz o resto. Se tudo o que voltaria é
  -- de quem saiu e a ação não criou nada que ainda esteja de pé, nada muda (a recusa diz por quê): voltar o Lenine com João e
  -- Roberto, que saíram, faria a vigia remanejar de novo e mandar outro aviso com outro *desfaz*.
  select coalesce(array_agg(c.id) filter (where not g.na_grade), '{}'), coalesce(array_agg(distinct c.payee_id) filter (where not g.na_grade), '{}'),
         count(*) filter (where g.na_grade)
    into v_f7_sai, v_f7_fora, v_f7_ficam
    from public.agenda_alocacoes c
    cross join lateral (select exists (select 1 from public.agenda_capacidade(c.dia, c.dia, p_hoje) k
                                        where k.payee_id = c.payee_id) as na_grade) g
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora;
  if cardinality(v_f7_fora) > 0 then
    v_f7_nomes := public._agenda_lista(array(select public._agenda_nome_curto(py.name) from public.payees py
                                              where py.id = any (v_f7_fora) order by py.name, py.id), null);
  end if;
  if cardinality(v_f7_fora) > 0 and v_f7_ficam = 0
     and not exists (select 1 from public.agenda_alocacoes a
                      where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')) then
    return jsonb_build_object('ok', false, 'status', 'saiu_da_equipe',
      'texto', format('Não dá para desfazer como estava: %s não %s mais na equipe, e era com %s que o %s estava. Nada mudou; ele volta à agenda com a equipe de agora.',
                      v_f7_nomes, case when cardinality(v_f7_fora) = 1 then 'está' else 'estão' end,
                      case when cardinality(v_f7_fora) = 1 then 'ele' else 'eles' end, v_nome));
  end if;
  -- FASE 7: fim
  -- FASE 7d: (correção G5) o cancelar da vigia em OS concluída por *entreguei* é só o efeito: o *desfaz* volta a entrega junto, pelo caminho dela, senão a OS segue concluída, com o plano de volta, e o
  -- tique seguinte cancela de novo. Se ela não volta, nada volta: a recusa dela.
  if v_a.tipo = 'cancelar' and v_a.origem = 'vigia' and (select so.status from public.service_orders so where so.id = v_os) = 'completed' then
    select x.id into v_7d_marco from public.agenda_acoes x
     where x.service_order_id = v_os and x.tipo in ('entregar', 'concluir') and x.executada and x.desfeita_em is null
       and x.criada_em <= v_a.criada_em and x.desfazivel_ate >= p_agora
     order by x.tipo = 'entregar' desc, x.criada_em desc, x.id desc limit 1;
    if v_7d_marco is not null then
      v_7d_rm := public._agenda_desfazer_marco(v_7d_marco, p_autor, p_via, p_hoje, p_agora);
      if not coalesce((v_7d_rm ->> 'ok')::boolean, false) then
        return v_7d_rm;
      end if;
    end if;
    -- (correção M9) a regra única: se a OS segue concluída depois do marco, o plano NÃO volta (a vigia tiraria de novo a cada tique), e o *desfaz* diz por quê. O cancelar segue desfazível: é o 2º *desfaz* que acha a conclusão
    if (select so.status from public.service_orders so where so.id = v_os) = 'completed' then
      if v_7d_rm is null then
        return jsonb_build_object('ok', false, 'texto', format('Não dá para voltar os dias do %s: ele segue concluído. Reabra a OS primeiro.', v_nome));
      end if;
      return jsonb_build_object('ok', true, 'acao_id', v_7d_rm -> 'acao_id', 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb,
        'texto', (v_7d_rm ->> 'texto') || ' ' ||
                 case when exists (select 1 from public.agenda_acoes x
                                    where x.service_order_id = v_os and x.tipo = 'concluir' and x.executada and x.desfeita_em is null
                                      and x.criada_em <= v_a.criada_em and x.desfazivel_ate >= p_agora)
                      then format('O %s segue concluído: mande *desfaz %s* de novo para voltar a conclusão.', v_nome,
                                  (select so.service_order_number from public.service_orders so where so.id = v_os))
                      else format('O %s segue concluído: os dias só voltam reabrindo a OS.', v_nome) end);
    end if;
  end if;
  -- FASE 7d: fim
  -- 1. O que a ação criou sai.
  for v_id in select a.id from public.agenda_alocacoes a
               where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada') order by a.dia, a.turno, a.id loop
    if (select estado from public.agenda_alocacoes where id = v_id) = 'fixada' then
      perform set_config('agenda.mexe_fixado', 'on', true);
    end if;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = v_id;
    perform set_config('agenda.mexe_fixado', 'off', true);
    v_canc := v_canc || v_id;
  end loop;
  -- 2. O que ela tirou volta, igual (mesma pessoa, dia, turno e presença), do que ainda não começou.
  for v_x in select c.* from public.agenda_alocacoes c
              where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
              order by c.dia, c.turno = 'tarde', c.payee_id, c.id loop
    -- FASE 7: (7a P7) o meio-dia de quem saiu da equipe não volta
    continue when v_x.id = any (v_f7_sai);
    -- FASE 7: fim
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id,
                                         fixado_por, reserva_de, condicao, condicao_tipo, condicao_ate, motivos)
    values (v_x.service_order_id, v_x.payee_id, v_x.dia, v_x.turno, v_x.presenca, v_x.tipo,
            case when v_x.fixado_por is not null then 'fixada' else 'publicada' end, v_x.origem, v_x.id,
            v_x.fixado_por, v_x.reserva_de, v_x.condicao, v_x.condicao_tipo, v_x.condicao_ate, v_x.motivos)
    returning id into v_id;
    v_novas := v_novas || v_id;
  end loop;
  -- 3. O status volta pela porta (a regra de não regredir o que começou continua valendo) e o espelho acompanha.
  if v_a.tipo = 'status' and v_a.status_antes is not null and v_os is not null then
    perform public.os_transicionar_status(v_os, v_a.status_antes, 'desfazer', null, p_autor, null, p_hoje, p_agora);
  elsif v_os is not null then
    if public._agenda_os_tem_dia(v_os, p_hoje) then
      if (select status from public.service_orders where id = v_os) in ('open', 'approved', 'awaiting_parts') then
        perform public.os_transicionar_status(v_os, 'scheduled', 'desfazer', null, p_autor, null, p_hoje, p_agora);
      end if;
    elsif (select status from public.service_orders where id = v_os) = 'scheduled' then
      perform public.os_transicionar_status(v_os, case when v_a.status_antes in ('open', 'approved', 'awaiting_parts')
                                                       then v_a.status_antes else 'approved' end,
                                            'desfazer', null, p_autor, null, p_hoje, p_agora);
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
  end if;

  v_dias := array(select a.dia from public.agenda_alocacoes a where a.id = any (v_novas) and a.tipo <> 'reserva');
  v_txt := case when cardinality(v_dias) > 0
                then format('Desfeito: o %s volta para %s, como estava.', public._agenda_rotulo_da_os(v_os), public._agenda_dias_texto(v_dias))
                when cardinality(v_novas) > 0 then format('Desfeito: a reserva do %s volta como estava.', public._agenda_rotulo_da_os(v_os))
                else format('Desfeito: o %s sai da agenda, como estava.', coalesce(public._agenda_rotulo_da_os(v_os), 'serviço')) end;
  -- FASE 7b: (correção da revisão da 7b, achado 18) desfazer a 2ª pessoa que o gestor pôs na dupla (as alocações com o motivo
  -- dupla_completa) tira só ela: o serviço continua marcado — o texto de antes dizia que ele saía da agenda
  if cardinality(v_novas) = 0 and cardinality(v_canc) > 0 and v_os is not null and public._agenda_os_tem_dia(v_os, p_hoje)
     and not exists (select 1 from public.agenda_alocacoes a where a.id = any (v_canc) and not coalesce(a.motivos ? 'dupla_completa', false)) then
    v_txt := format('Desfeito: tirei %s do %s %s; o resto do serviço fica como estava.',
                    public._agenda_lista(array(select distinct public._agenda_nome_curto(py.name)
                                                 from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                                                where a.id = any (v_canc) order by 1)),
                    public._agenda_rotulo_da_os(v_os),
                    public._agenda_meios_frase((select jsonb_agg(jsonb_build_object('dia', a.dia, 'turno', a.turno) order by a.dia, a.turno)
                                                  from public.agenda_alocacoes a where a.id = any (v_canc))));
  end if;
  -- FASE 7b: fim
  -- FASE 7: (7a P7) e diz o que não voltou
  if cardinality(v_f7_fora) > 0 then
    v_txt := v_txt || format(' %s não %s mais na equipe: os dias %s não voltam.', v_f7_nomes,
                             case when cardinality(v_f7_fora) = 1 then 'está' else 'estão' end,
                             case when cardinality(v_f7_fora) = 1 then 'dele' else 'deles' end);
  end if;
  -- FASE 7: fim
  -- FASE 7d: (correção G5) os 2 "Desfeito", na ordem em que aconteceram
  v_txt := coalesce((v_7d_rm ->> 'texto') || ' ', '') || v_txt;
  -- FASE 7d: fim
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, critica,
                                   versao_depois, alocacoes_criadas, alocacoes_canceladas, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
          v_a.os_ids, v_a.proposta_id, false, (public._agenda_cfg()).versao_plano, v_novas, v_canc,
          jsonb_build_object('acao', v_a.id), jsonb_build_object('alocacoes', to_jsonb(v_novas)), left(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_alocacoes set acao_id = v_acao where id = any (v_novas);
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;

  -- Desfazer uma decisão crítica não a reabre: a decisão volta ao dono como pergunta nova, do mesmo tipo.
  if v_a.critica and v_a.pergunta_id is not null then
    select * into v_q from public.agenda_perguntas where id = v_a.pergunta_id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao,
                                         recomendacao_texto, versao_base, modo, criada_em)
    values (v_q.tipo, left(v_q.chave || ':refeita:' || left(v_acao::text, 8), 200), v_q.service_order_id, v_q.os_ids, v_q.perda_em,
            v_q.texto, v_q.opcoes, v_q.recomendacao, v_q.recomendacao_texto, (public._agenda_cfg()).versao_plano, v_q.modo, p_agora)
    on conflict (chave, modo) where estado = 'aberta' do nothing;
    v_txt := format('Desfeito. A decisão sobre o %s volta a ficar com você.', v_nome);
  end if;
  -- FASE 3: o replano que a ausência da equipe causou ("não vou" ou o silêncio até as 9h): desfazer também tira a ausência
  -- daquele dia (senão a vigia replanejaria de novo no tique seguinte). "Se ele estiver lá, *desfaz Vanderlei*."
  update public.agenda_disponibilidade d set substituida_em = p_agora
   where d.substituida_em is null
     and d.id in (select (e.depois ->> 'disponibilidade')::uuid from public.agenda_acoes e
                   where e.tipo = 'equipe' and e.depois ->> 'disponibilidade' is not null
                     and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text);
  -- FASE 3: fim
  -- FASE 5: o replano que o pedido de dia do cliente causou, desfeito direto (sem a ação do cliente): o pedido sai junto (o
  -- bem indisponível e o "não antes de" voltam; senão a vigia replanejaria de novo no tique seguinte) e a ação do cliente
  -- fica desfeita. Quem desfaz pela ação do cliente (_agenda_desfazer_cliente) liga agenda.desfazer_cliente e faz isso ela.
  if coalesce(current_setting('agenda.desfazer_cliente', true), '') <> 'on' then
    for v_x in select e.id from public.agenda_acoes e
                where e.tipo = 'cliente' and e.origem = 'cliente' and e.executada and e.desfeita_em is null
                  and e.depois ->> 'efeito' = 'replanejou'
                  and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text loop
      perform public._agenda_cliente_restaurar_pedido(v_x.id, p_agora);
      update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_x.id;
    end loop;
  end if;
  -- FASE 5: fim
  -- FASE 7d: (7d P5, R6.7c-1) o replano do "Segure o dia", desfeito direto (sem a ação local): o "não antes de" volta junto, senão a vigia tiraria o
  -- dia de novo no tique seguinte; e a ação local fica desfeita. Quem desfaz pela ação local liga agenda.desfazer_local e faz isso ela.
  if coalesce(current_setting('agenda.desfazer_local', true), '') <> 'on' then
    for v_x in select e.id from public.agenda_acoes e
                where e.tipo = 'local' and e.executada and e.desfeita_em is null
                  and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text loop
      perform public._agenda_local_restaurar(v_x.id, p_autor, p_agora);
      update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_x.id;
    end loop;
  end if;
  -- FASE 7d: fim
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

create or replace function public.agenda_rascunho_desfazer(p_autor uuid, p_canal text, p_alvo text default null,
                                                           p_trecho text default null,
                                                           p_hoje date default public._hoje_brt(),
                                                           p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_rec   jsonb := public._agenda_pedido_recusa(p_canal, p_trecho, 'agenda_rascunho_desfazer');
  v_ref   jsonb;
  v_ids   uuid[];
  v_a     public.agenda_acoes%rowtype;
  v_quando text;
  v_frase text;
  v_txt   text;
  -- FASE 7d: (correção M1) o marco que o *desfaz* do cancelar da vigia volta junto
  v_7d_marco public.agenda_acoes%rowtype;
  -- FASE 7d: fim
begin
  if v_rec is not null then
    return v_rec;
  end if;
  v_ref := public.agenda_acao_desfazivel(p_alvo, p_hoje, p_agora);
  if v_ref ->> 'status' is distinct from 'ok' then
    return public._agenda_recusa(v_ref ->> 'texto', 'desfazer_' || coalesce(v_ref ->> 'status', 'nenhuma'),
      coalesce((select jsonb_agg(coalesce(e ->> 'texto', e #>> '{}') order by o)
                  from jsonb_array_elements(case when jsonb_typeof(v_ref -> 'opcoes') = 'array' then v_ref -> 'opcoes' else '[]'::jsonb end)
                       with ordinality t(e, o)), '[]'::jsonb));
  end if;
  v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_ref -> 'acao_ids', jsonb_build_array(v_ref ->> 'acao_id'))) x);
  select * into v_a from public.agenda_acoes where id = v_ids[1];
  -- o que já começou não se desfaz (a mesma régua de agenda_desfazer): melhor dizer agora do que no *grava*
  if exists (select 1 from public.agenda_acoes ac join public.agenda_alocacoes a on a.id = any (ac.alocacoes_criadas)
              where ac.id = any (v_ids) and a.estado in ('publicada', 'fixada')
                and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
    return public._agenda_recusa(format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.',
                                        coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                                                    join public.clients cl on cl.id = so.client_id where so.id = v_a.service_order_id),
                                                 'serviço')), 'ja_comecou');
  end if;
  v_quando := format('mudei %s às %s',
                     case when v_a.dia = p_hoje then 'hoje' when v_a.dia = p_hoje - 1 then 'ontem' else public._dia_curto(v_a.dia) end,
                     to_char(v_a.criada_em at time zone 'America/Sao_Paulo', 'HH24:MI'));
  v_frase := case when cardinality(v_ids) > 1
                  then format('a publicação da semana (%s; %s)', public._agenda_plural(cardinality(v_ids), 'serviço', 'serviços'), v_quando)
                  else format('%s (%s)', rtrim(v_a.texto, '.'), v_quando) end;
  -- FASE 7d: (correção M1) no bloco G5 de agenda_desfazer, com o marco disponível, o *grava* volta a conclusão e cancela a cobrança dela: a releitura diz antes. A mesma busca do marco.
  -- Sem a conclusão no marco (concluí e entreguei separados), só a entrega volta, sem dinheiro, e o *grava* diz o que falta
  if cardinality(v_ids) = 1 and v_a.tipo = 'cancelar' and v_a.origem = 'vigia'
     and (select so.status from public.service_orders so where so.id = v_a.service_order_id) = 'completed' then
    select x.* into v_7d_marco from public.agenda_acoes x
     where x.service_order_id = v_a.service_order_id and x.tipo in ('entregar', 'concluir') and x.executada and x.desfeita_em is null
       and x.criada_em <= v_a.criada_em and x.desfazivel_ate >= p_agora
     order by x.tipo = 'entregar' desc, x.criada_em desc, x.id desc limit 1;
    v_frase := v_frase || case when v_7d_marco.tipo = 'concluir' then '. A conclusão volta junto; a cobrança da conclusão, se houver, é cancelada'
                               when v_7d_marco.depois ? 'concluir_acao' then '. A entrega e a conclusão voltam junto; a cobrança da conclusão, se houver, é cancelada'
                               else '' end;
  end if;
  -- FASE 7d: fim
  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'desfazer', 'desfazer:' || v_ids[1]::text, v_a.service_order_id,
             jsonb_build_object('grupo', 'desfazer:' || v_ids[1]::text, 'rotulo_grupo', 'Desfaço', 'acao_ids', to_jsonb(v_ids),
                                'frase_pronta', v_frase),
             p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

create or replace function public._agenda_aplicar_planejar(p_autor uuid, p_os uuid, p_dados jsonb, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  d           jsonb := coalesce(p_dados, '{}'::jsonb);
  v_old       public.os_planejamento%rowtype;
  v_new       public.os_planejamento%rowtype;
  v_eq_antes  jsonb;
  v_eq_depois jsonb;
  v_antes     jsonb := '{}'::jsonb;
  v_depois    jsonb := '{}'::jsonb;
  v_k         text;
  -- FASE 5: o prometido de antes e o gravado
  v_prom_antes jsonb;
  v_prom      jsonb;
  -- FASE 5: fim
  -- FASE 7d: (7d P7; §5.7) o que o dono disse do local e do bem: as chaves, a hora do *grava*, os autorizados, o antes e o depois da ação e as perguntas que ele fechou
  c_7d_chaves constant text[] := array['local_id', 'bem_situacao', 'bem_exige', 'descer_quem', 'entrada_em', 'retirada_em', 'viagem', 'autorizados'];
  v_7d_tem    boolean := coalesce(p_dados, '{}'::jsonb) ?| array['local_id', 'bem_situacao', 'bem_exige', 'descer_quem', 'entrada_em', 'retirada_em', 'viagem', 'autorizados'];
  v_7d_agora  timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  v_7d_ids    uuid[];
  v_7d_vig_a  uuid[];
  v_7d_vig_d  uuid[];
  v_7d_linhas jsonb;
  v_7d_lin_d  jsonb;
  v_7d_local  uuid;
  v_7d_antes  jsonb := '{}'::jsonb;
  v_7d_dep    jsonb := '{}'::jsonb;
  v_7d_q      public.agenda_perguntas%rowtype;
  v_7d_item   jsonb;
  v_7d_abert  uuid[];
  v_7d_fech   uuid[] := '{}';
  v_7d_trecho text;
  v_7d_lin    jsonb;   -- (correção O2, O3) a linha de agenda_locais que o *grava* achou ou criou
  v_7d_recolhido uuid; -- (correção G6) a linha que esta correção deixou sem uso
  -- FASE 7d: fim
begin
  if not exists (select 1 from public.service_orders where id = p_os) then
    raise exception 'o serviço % não existe mais', coalesce(d ->> 'numero', p_os::text) using errcode = 'P0001';
  end if;
  insert into public.os_planejamento (service_order_id) values (p_os) on conflict (service_order_id) do nothing;
  -- FASE 5: o que o dono disse ao cliente vira o prometido (fonte dono; a 1ª promessa fica em prometido_original_ate; o
  -- histórico ganha a linha própria, pelo _agenda_cliente_gravar_prometido). Gravado antes de ler a linha: o diff abaixo é
  -- só do resto. Só o prometido na linha = nada mais a gravar.
  if jsonb_typeof(d -> 'prometido') = 'object' then
    select jsonb_build_object('tipo', pl.prometido_tipo, 'de', pl.prometido_de, 'ate', pl.prometido_ate, 'fonte', pl.prometido_fonte)
      into v_prom_antes from public.os_planejamento pl where pl.service_order_id = p_os;
    v_prom := public._agenda_cliente_gravar_prometido(p_os, d #>> '{prometido,tipo}', (d #>> '{prometido,de}')::date,
                (d #>> '{prometido,ate}')::date, 'dono', null,
                coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now()), p_trecho);
    -- FASE 7b: (7b P2) com a dupla na mesma linha, o resto da linha ainda grava (não volta só com o prometido)
    if not (d ? 'dupla') then
    -- FASE 7b: fim
    -- FASE 7d: (7d P7) com o local ou o bem na mesma linha, o resto da linha ainda grava: a volta de baixo só serve ao prometido sozinho
    if not (d ?| c_7d_chaves) then
    -- FASE 7d: fim
    if not (d ?| array['dias', 'equipe', 'dono', 'precisa_ate', 'bem', 'nao_antes_de', 'escopo_em_aberto', 'escopo_decidido',
                       'congelada_ate', 'prioridade', 'sem_material', 'adiantavel_patio', 'servico_cliente']) then
      return jsonb_build_object('antes', jsonb_build_object('prometido', v_prom_antes), 'depois', jsonb_build_object('prometido', v_prom));
    end if;
    -- FASE 7d: (7d P7) fecha o "com o local ou o bem na mesma linha"
    end if;
    -- FASE 7d: fim
    -- FASE 7b: (7b P2) fecha o "com a dupla na mesma linha"
    end if;
    -- FASE 7b: fim
  end if;
  -- FASE 5: fim
  select * into v_old from public.os_planejamento where service_order_id = p_os for update;
  v_new := v_old;
  -- FASE 7b: (7b P2) a dupla dita (o histórico abaixo guarda o antes e o depois): nao = 1 pessoa (sem a inferência), todos, ou
  -- inicio/fim com os meios-dias
  if d ? 'dupla' then
    v_new.dupla_dita := d ->> 'dupla';
    v_new.dupla_meios := case when d ->> 'dupla' in ('inicio', 'fim') then (d ->> 'dupla_meios')::smallint end;
    v_new.dupla_motivo := left('você disse: ' || public._agenda_rascunho_frase('planejar',
                                 jsonb_build_object('dupla', d ->> 'dupla', 'dupla_meios', d -> 'dupla_meios')), 80);
    v_new.dupla_em := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  end if;
  -- FASE 7b: fim

  if d ? 'dias' then
    v_new.dias := (d ->> 'dias')::numeric;
    v_new.estimativa_fonte := d ->> 'estimativa_fonte';
    v_new.estimativa_em := now();
  end if;
  if d ? 'dono' then v_new.dono_presenca := d ->> 'dono'; end if;
  if d ? 'precisa_ate' then v_new.precisa_ate := (d ->> 'precisa_ate')::date; end if;
  if d ? 'bem' then
    v_new.bem_indisponivel := case when d #>> '{bem,modo}' = 'livre' then '{}'::datemultirange
                                   else datemultirange(daterange((d #>> '{bem,de}')::date, (d #>> '{bem,livre_em}')::date, '[)')) end;
  end if;
  if d ? 'nao_antes_de' then
    v_new.nao_antes_de := (d ->> 'nao_antes_de')::date;
    v_new.nao_antes_motivo := d ->> 'nao_antes_motivo';
  end if;
  if d ? 'escopo_em_aberto' then v_new.escopo_em_aberto := d ->> 'escopo_em_aberto'; end if;
  if d ? 'escopo_decidido' then v_new.escopo_decidido := d ->> 'escopo_decidido'; end if;
  if d ? 'congelada_ate' then
    v_new.congelada_ate := (d ->> 'congelada_ate')::date;
    v_new.revisar_em := (d ->> 'revisar_em')::date;
  end if;
  if d ? 'prioridade' then v_new.prioridade_manual := (d ->> 'prioridade')::smallint; end if;
  if d ? 'sem_material' then
    v_new.material_conferido_em := case when (d ->> 'sem_material')::boolean then now() end;
  end if;
  -- FASE 2: o que dá para adiantar no pátio (null = o dono tirou).
  if d ? 'adiantavel_patio' then
    v_new.adiantavel_patio_dias := (d ->> 'adiantavel_patio')::numeric;
  end if;
  -- FASE 5: como o serviço é dito ao cliente
  if d ? 'servico_cliente' then
    v_new.servico_cliente := d ->> 'servico_cliente';
  end if;
  -- FASE 5: fim

  -- FASE 7d: (7d P7; §5.7) o que o dono disse do local e do bem, fonte dono. Vai para a linha aqui, antes de ler o local resolvido dos autorizados; o histórico abaixo guarda o antes
  -- e o depois (o update de antes não tem estas colunas). A chegada e a saída têm uma fonte só: entrada_coerente.
  if v_7d_tem then
    -- (correção O2, O3) o lugar novo e a casa do cliente viram linha de agenda_locais aqui, no *grava*, e daqui em diante são um local como os outros
    if coalesce((d ->> 'local_casa')::boolean, false) or nullif(d ->> 'local_novo', '') is not null then
      v_7d_lin := case when coalesce((d ->> 'local_casa')::boolean, false) then public._agenda_local_da_casa(p_os, p_autor)
                       else public._agenda_local_criar(d ->> 'local_novo', d ->> 'local_municipio', d ->> 'local_uf', p_autor) end;
      d := (d - 'local_novo') || jsonb_build_object('local_id', v_7d_lin ->> 'id', 'local_nome', v_7d_lin ->> 'nome');
      -- (correção G6) a casa sem cidade leva a que o dono disse ("na casa dele em Porto Belo"); o cadastro do cliente não muda
      -- (correção A1) só na linha da casa: o rascunho junta as frases, e "em Penha" depois da casa não pode levar a cidade dela
      if coalesce((d ->> 'local_casa')::boolean, false) and coalesce((d ->> 'local_casa_dita')::boolean, false) then
        update public.agenda_locais x set municipio = d ->> 'local_casa_em', uf = d ->> 'local_casa_uf', atualizado_por = p_autor
         where x.id = (v_7d_lin ->> 'id')::uuid;
      end if;
    end if;
    if d ? 'local_id' then
      -- (correção M8) a linha que saiu de uso entre a releitura e o *grava* volta, sob a trava de _agenda_local_criar: sem isso diz "Gravado" e aponta para uma linha inativa. A linha ativa não toma trava nova
      if exists (select 1 from public.agenda_locais x where x.id = (d ->> 'local_id')::uuid and not x.ativo and x.tipo in ('outro', 'casa_cliente')) then
        perform pg_advisory_xact_lock(hashtext('agenda_local_criar'));
        update public.agenda_locais x set ativo = true, atualizado_por = p_autor
         where x.id = (d ->> 'local_id')::uuid and not x.ativo and x.tipo in ('outro', 'casa_cliente');
      end if;
      v_new.local_id := (d ->> 'local_id')::uuid;
      v_new.local_fonte := case when d ->> 'local_id' is not null then 'dono' end;
      v_new.local_em := case when d ->> 'local_id' is not null then v_7d_agora end;
    end if;
    if d ? 'bem_situacao' then
      v_new.bem_situacao := d ->> 'bem_situacao';
      v_new.bem_situacao_fonte := 'dono';
      v_new.bem_situacao_em := v_7d_agora;
    end if;
    if d ? 'bem_exige' then v_new.bem_exige := d ->> 'bem_exige'; end if;
    if d ? 'descer_quem' then v_new.descer_quem := d ->> 'descer_quem'; end if;
    if d ? 'viagem' then v_new.viagem := d ->> 'viagem'; end if;
    if d ?| array['entrada_em', 'retirada_em'] then
      if d ? 'entrada_em' then v_new.entrada_em := (d ->> 'entrada_em')::date; end if;
      if d ? 'retirada_em' then v_new.retirada_em := (d ->> 'retirada_em')::date; end if;
      v_new.entrada_fonte := case when coalesce(v_new.entrada_em, v_new.retirada_em) is not null then 'dono' end;
      -- o que mudou entre a releitura e o *grava*: a frase dele, não "o banco recusou"
      if v_new.entrada_em >= v_new.retirada_em then
        raise exception 'a saída (%) tem de ser depois da chegada (%)', public._dia_curto(v_new.retirada_em), public._dia_curto(v_new.entrada_em) using errcode = 'P0001';
      end if;
    end if;
    update public.os_planejamento
       set local_id = v_new.local_id, local_fonte = v_new.local_fonte, local_em = v_new.local_em,
           bem_situacao = v_new.bem_situacao, bem_situacao_fonte = v_new.bem_situacao_fonte, bem_situacao_em = v_new.bem_situacao_em,
           bem_exige = v_new.bem_exige, descer_quem = v_new.descer_quem, viagem = v_new.viagem,
           entrada_em = v_new.entrada_em, retirada_em = v_new.retirada_em, entrada_fonte = v_new.entrada_fonte
     where service_order_id = p_os;
    -- (correção G6) corrigir limpa: a linha que saiu da OS, sem conferir e sem outro uso, fica inativa, pela regra do *desfaz*; o *desfaz* desta correção a reativa
    if v_old.local_id is not null and v_old.local_id is distinct from v_new.local_id and public._agenda_local_recolher(v_old.local_id, p_autor) then
      v_7d_recolhido := v_old.local_id;
    end if;
    -- A lista dita substitui a anterior, como a equipe: a linha nunca se apaga (quem saiu ganha revogado_em). O antes vai inteiro para a ação: o *desfaz* volta linha por linha.
    if d ? 'autorizados' then
      select coalesce(jsonb_agg(to_jsonb(x) order by x.payee_id), '[]'::jsonb) into v_7d_linhas
        from public.os_autorizados x where x.service_order_id = p_os;
      v_7d_vig_a := array(select x.payee_id from public.os_autorizados x where x.service_order_id = p_os and x.revogado_em is null order by 1);
      v_7d_ids := array(select distinct (e ->> 'payee_id')::uuid from jsonb_array_elements(d -> 'autorizados') e order by 1);
      update public.os_autorizados x set revogado_em = v_7d_agora
       where x.service_order_id = p_os and x.revogado_em is null and not (x.payee_id = any (v_7d_ids));
      if cardinality(v_7d_ids) > 0 then
        -- (correção O6) com o local suposto, a lista fica sem local (nulo = desta OS): ela sobrevive ao dono dizer o local depois
        select case when coalesce((x.r ->> 'suposicao')::boolean, false) then null else (x.r ->> 'local_id')::uuid end into v_7d_local
          from (select public._agenda_local_resolvido(p_os, p_hoje) as r) x;
        insert into public.os_autorizados (service_order_id, payee_id, local_id, valido_ate, fonte, trecho, criado_em, criado_por)
        select p_os, u.id, v_7d_local, null, 'dono', left(p_trecho, 300), v_7d_agora, p_autor from unnest(v_7d_ids) u(id)
        on conflict (service_order_id, payee_id) do update
          set local_id = excluded.local_id, valido_ate = null, fonte = excluded.fonte, trecho = excluded.trecho, revogado_em = null,
              criado_em = excluded.criado_em, criado_por = excluded.criado_por
          -- dizer de novo o que já está não mexe na linha
          where (os_autorizados.local_id, os_autorizados.valido_ate, os_autorizados.fonte, os_autorizados.revogado_em)
                is distinct from (excluded.local_id, null::date, excluded.fonte, null::timestamptz);
      end if;
      v_7d_vig_d := v_7d_ids;
      select coalesce(jsonb_agg(to_jsonb(x) order by x.payee_id), '[]'::jsonb) into v_7d_lin_d
        from public.os_autorizados x where x.service_order_id = p_os;
      -- a mesma lista pode ter mudado por dentro (o local, a validade, a fonte): a comparação é das linhas, não dos nomes
      if v_7d_linhas is distinct from v_7d_lin_d then
        v_antes := v_antes || jsonb_build_object('autorizados', to_jsonb(v_7d_vig_a));
        v_depois := v_depois || jsonb_build_object('autorizados', to_jsonb(v_7d_vig_d));
      end if;
    end if;
  end if;
  -- FASE 7d: fim
  select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'turnos', e.turnos) order by e.payee_id), '[]'::jsonb)
    into v_eq_antes
    from public.os_planejamento_equipe e where e.service_order_id = p_os;
  if d ? 'equipe' then
    delete from public.os_planejamento_equipe where service_order_id = p_os;
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos)
    select p_os, (e ->> 'payee_id')::uuid, e ->> 'turnos' from jsonb_array_elements(d -> 'equipe') e;
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'turnos', e.turnos) order by e.payee_id), '[]'::jsonb)
      into v_eq_depois
      from public.os_planejamento_equipe e where e.service_order_id = p_os;
  else
    v_eq_depois := v_eq_antes;
  end if;

  -- O histórico guarda só o que mudou: {campo: antes} e {campo: depois}.
  for v_k in select key from jsonb_each(to_jsonb(v_new) - array['historico', 'atualizado_em', 'atualizado_por', 'trecho', 'estimativa_em'])
  loop
    if to_jsonb(v_old) -> v_k is distinct from to_jsonb(v_new) -> v_k then
      v_antes := v_antes || jsonb_build_object(v_k, to_jsonb(v_old) -> v_k);
      v_depois := v_depois || jsonb_build_object(v_k, to_jsonb(v_new) -> v_k);
    end if;
  end loop;
  if v_eq_antes is distinct from v_eq_depois then
    v_antes := v_antes || jsonb_build_object('equipe', v_eq_antes);
    v_depois := v_depois || jsonb_build_object('equipe', v_eq_depois);
  end if;

  update public.os_planejamento
     set dias = v_new.dias, estimativa_fonte = v_new.estimativa_fonte, estimativa_em = v_new.estimativa_em,
         dono_presenca = v_new.dono_presenca, precisa_ate = v_new.precisa_ate, bem_indisponivel = v_new.bem_indisponivel,
         nao_antes_de = v_new.nao_antes_de, nao_antes_motivo = v_new.nao_antes_motivo,
         escopo_em_aberto = v_new.escopo_em_aberto, escopo_decidido = v_new.escopo_decidido,
         congelada_ate = v_new.congelada_ate, revisar_em = v_new.revisar_em, prioridade_manual = v_new.prioridade_manual,
         material_conferido_em = v_new.material_conferido_em,
         adiantavel_patio_dias = v_new.adiantavel_patio_dias,   -- FASE 2
         -- FASE 5: como o serviço é dito ao cliente
         servico_cliente = v_new.servico_cliente,
         -- FASE 5: fim
         trecho = public._agenda_corta(p_trecho, 500),
         historico = public._os_material_historico(v_old.historico, jsonb_build_object(
           'em', p_hoje, 'autor', p_autor, 'trecho', public._agenda_corta(p_trecho, 500), 'antes', v_antes, 'depois', v_depois)),
         atualizado_em = now(), atualizado_por = p_autor
   where service_order_id = p_os;
  -- FASE 7b: (7b P2) a dupla dita vai para a linha (o update acima é o de antes, sem as colunas da dupla)
  if d ? 'dupla' then
    update public.os_planejamento
       set dupla_dita = v_new.dupla_dita, dupla_meios = v_new.dupla_meios, dupla_motivo = v_new.dupla_motivo,
           dupla_em = v_new.dupla_em
     where service_order_id = p_os;
  end if;
  -- FASE 7b: fim
  -- FASE 7d: (correção O21) "já está livre" (o bem sem indisponibilidade, modo livre) fecha a bem_livre mesmo sem campo do local na linha
  if d #>> '{bem,modo}' = 'livre' then
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'você disse que o bem está livre'
     where chave = 'bem_livre:' || p_os and estado = 'aberta';
  end if;
  -- FASE 7d: fim
  -- FASE 7d: (7d P7) o dono vence e o *desfaz* volta tudo.
  -- (a) A pergunta local aberta da OS: o sim dela gravaria depois, por cima do que o dono disse, o que o cliente falou. Fecha quando ele disse o que ela gravaria (a sem leitura, que
  -- pede "me diga onde é", com o local, o bem ou a chegada). "Tirei o local" não diz onde é: ela fica.
  -- (b) A combinar e a acesso: o sim é a palavra do próprio dono, com a data escrita, mas o que ele disse pode já ter resolvido; o tique levaria até 15 minutos. O mesmo resolvedor, agora.
  -- (c) A ação local: só o que mudou de fato, mais a pergunta que fechou. Sem as chaves novas, nada disto roda: os_planejar_pela_tela e as linhas de antes não têm ação.
  if v_7d_tem then
    select q.* into v_7d_q from public.agenda_perguntas q where q.chave = 'local:' || p_os and q.estado = 'aberta' limit 1;
    if found then
      v_7d_item := v_7d_q.opcoes -> 0 #> '{efeito,item}';
      if d ->> 'local_id' is not null or coalesce((d ->> 'local_casa')::boolean, false)
         or (d ? 'bem_situacao' and (v_7d_item is null or v_7d_item ->> 'situacao' is not null))
         or (d ? 'descer_quem' and v_7d_item ->> 'descer_quem' is not null)
         or (d ->> 'entrada_em' is not null and v_7d_item is null) then
        update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'você disse onde é' where id = v_7d_q.id;
        v_7d_fech := v_7d_fech || v_7d_q.id;
      end if;
    end if;
    -- (correção O21) a bem_livre fecha quando o dono diz onde o bem está: no pátio, ou num lugar em que ele não está com o cliente. O *desfaz* a devolve, como as outras
    v_7d_q := null;
    select q.* into v_7d_q from public.agenda_perguntas q where q.chave = 'bem_livre:' || p_os and q.estado = 'aberta' limit 1;
    if v_7d_q.id is not null
       and (d ->> 'bem_situacao' in ('patio', 'agua', 'seco', 'garagem_seca')
            or exists (select 1 from public.agenda_locais x where x.id = (d ->> 'local_id')::uuid and x.tipo like 'patio\_%')) then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'você disse onde o bem está' where id = v_7d_q.id;
      v_7d_fech := v_7d_fech || v_7d_q.id;
    end if;
    v_7d_abert := array(select q.id from public.agenda_perguntas q where q.service_order_id = p_os and q.tipo in ('combinar', 'acesso') and q.estado = 'aberta');
    if cardinality(v_7d_abert) > 0 then
      perform public._agenda_local_resolver(p_hoje, v_7d_agora);
      v_7d_fech := v_7d_fech || array(select q.id from public.agenda_perguntas q where q.id = any (v_7d_abert) and q.estado <> 'aberta');
    end if;

    if (v_old.local_id, v_old.local_fonte) is distinct from (v_new.local_id, v_new.local_fonte) then
      v_7d_antes := v_7d_antes || jsonb_build_object('local_id', v_old.local_id, 'local_fonte', v_old.local_fonte, 'local_em', v_old.local_em);
      v_7d_dep := v_7d_dep || jsonb_build_object('local_id', v_new.local_id, 'local_fonte', v_new.local_fonte, 'local_em', v_new.local_em)
                  || case when v_7d_recolhido is not null then jsonb_build_object('local_recolhido', v_7d_recolhido) else '{}'::jsonb end;
    end if;
    if (v_old.bem_situacao, v_old.bem_situacao_fonte) is distinct from (v_new.bem_situacao, v_new.bem_situacao_fonte) then
      v_7d_antes := v_7d_antes || jsonb_build_object('bem_situacao', v_old.bem_situacao, 'bem_situacao_fonte', v_old.bem_situacao_fonte, 'bem_situacao_em', v_old.bem_situacao_em);
      v_7d_dep := v_7d_dep || jsonb_build_object('bem_situacao', v_new.bem_situacao, 'bem_situacao_fonte', v_new.bem_situacao_fonte, 'bem_situacao_em', v_new.bem_situacao_em);
    end if;
    if v_old.bem_exige is distinct from v_new.bem_exige then
      v_7d_antes := v_7d_antes || jsonb_build_object('bem_exige', v_old.bem_exige);
      v_7d_dep := v_7d_dep || jsonb_build_object('bem_exige', v_new.bem_exige);
    end if;
    if v_old.descer_quem is distinct from v_new.descer_quem then
      v_7d_antes := v_7d_antes || jsonb_build_object('descer_quem', v_old.descer_quem);
      v_7d_dep := v_7d_dep || jsonb_build_object('descer_quem', v_new.descer_quem);
    end if;
    if v_old.viagem is distinct from v_new.viagem then
      v_7d_antes := v_7d_antes || jsonb_build_object('viagem', v_old.viagem);
      v_7d_dep := v_7d_dep || jsonb_build_object('viagem', v_new.viagem);
    end if;
    if (v_old.entrada_em, v_old.retirada_em, v_old.entrada_fonte) is distinct from (v_new.entrada_em, v_new.retirada_em, v_new.entrada_fonte) then
      v_7d_antes := v_7d_antes || jsonb_build_object('entrada_em', v_old.entrada_em, 'retirada_em', v_old.retirada_em, 'entrada_fonte', v_old.entrada_fonte);
      v_7d_dep := v_7d_dep || jsonb_build_object('entrada_em', v_new.entrada_em, 'retirada_em', v_new.retirada_em, 'entrada_fonte', v_new.entrada_fonte);
    end if;
    if v_7d_linhas is distinct from v_7d_lin_d then
      v_7d_antes := v_7d_antes || jsonb_build_object('autorizados_linhas', v_7d_linhas);
      v_7d_dep := v_7d_dep || jsonb_build_object('autorizados', to_jsonb(v_7d_ids), 'autorizados_vigentes', to_jsonb(v_7d_vig_d));
    end if;
    if v_7d_antes <> '{}'::jsonb or cardinality(v_7d_fech) > 0 then
      select x.trecho into v_7d_trecho from public.os_planejamento x where x.service_order_id = p_os;
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto, motivo, autor, desfazivel_ate)
      values (clock_timestamp(), p_hoje, true, 'dono', 'local', p_os, array[p_os], false, v_7d_antes || jsonb_build_object('trecho', v_old.trecho),
              v_7d_dep || jsonb_build_object('trecho', v_7d_trecho, 'efeito', 'planejar', 'perguntas_fechadas', to_jsonb(v_7d_fech),
                                             'item', jsonb_build_object('cliente', d ->> 'curto')),
              public._agenda_corta(concat_ws(': ', d ->> 'curto', array_to_string(public._agenda_planejar_linhas(d), ' ')), 400), 'você disse', p_autor,
              v_7d_agora + (public._agenda_cfg()).desfazer_validade);
    end if;
  end if;
  -- FASE 7d: fim
  return jsonb_build_object('antes', v_antes, 'depois', v_depois);
end;
$function$;

create or replace function public.agenda_rascunho_planejar(p_autor uuid, p_canal text, p_os text, p_dados jsonb,
                                                           p_trecho text, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  d        jsonb := coalesce(p_dados, '{}'::jsonb);
  c_campos constant text[] := array['dias', 'com_quem', 'dono', 'precisa_ate', 'bem_fora', 'bem_livre_em', 'nao_antes_de',
                                    -- FASE 7d: (7d P7; §5.7, R6.3-10) os 8 do local e do bem: 25 com os 17 de antes
                                    'local', 'bem_onde', 'bem_exige', 'descer_quem', 'chega_em', 'sai_em', 'viagem', 'autorizados',
                                    -- FASE 7d: fim
                                    'nao_antes_motivo', 'escopo_em_aberto', 'escopo_decidido', 'congelar_ate', 'revisar_em',
                                    'prioridade', 'sem_material', 'aceitar_sugestao', 'limpar',
                                    'adiantavel_patio'];   -- FASE 2: adiantavel_patio
  -- O que o dono desfaz ("pode voltar", "tira da espera", "não tem mais data mínima", "o cliente não tem mais prazo",
  -- "o escopo está resolvido"): o campo volta a vazio.
  c_limpar constant text[] := array['espera', 'nao_antes', 'prazo', 'escopo', 'patio'];   -- FASE 2: patio
  v_limpar text[] := '{}';
  v_k      text;
  v_ro     jsonb;
  v_os     uuid;
  v_out    jsonb := '{}'::jsonb;
  v_n      numeric;
  v_sug    jsonb;
  v_x      jsonb;
  v_rp     jsonb;
  v_turnos text;
  v_equipe jsonb := '[]'::jsonb;
  v_dt     jsonb;
  v_dt2    jsonb;
  v_bem    text;
  v_txt    text;
  v_dias_os numeric;   -- FASE 2
  -- FASE 5: o que foi dito ao cliente e como o serviço é dito a ele
  c_serv_max constant int := 40;   -- estrutural: o serviço aparece duas vezes no aviso de atraso (que tem de caber em 400)
  v_prom   text;
  v_serv   text;
  v_dtp    jsonb;
  -- FASE 5: fim
  -- FASE 7b: (7b P2; R4.3(b)) a dupla dita pelo planejar
  v_7b_dupla text;
  v_7b_meios_txt text;
  v_7b_tem_meios boolean := false;
  v_7b_meios int;
  v_7b_tec   text[];
  v_7b_aviso text;
  -- FASE 7b: fim
  -- FASE 7d: (7d P7; §5.7) o que o dono desfaz do local e do bem, o local, os autorizados e as datas contra o que já foi dito
  c_7d_limpar constant text[] := array['local', 'entrada', 'retirada', 'viagem', 'autorizados'];
  c_7d_quem_min constant int := 2;    -- estrutural: o CHECK de os_planejamento.descer_quem
  c_7d_quem_max constant int := 80;   -- estrutural: o CHECK de os_planejamento.descer_quem
  c_7d_volta    constant int := 7;    -- decisão do fio (G10): a chegada sem verbo no passado não volta mais do que isso
  v_7d_limpar text[] := '{}';
  v_7d_rl    jsonb;
  v_7d_txt   text;
  v_7d_aut   jsonb := '[]'::jsonb;
  v_7d_velho jsonb;
  v_7d_ent   date;
  v_7d_sai   date;
  v_7d_novo  jsonb;   -- (correção O2) o lugar novo
  v_7d_mun   jsonb;   -- (correção O2) a cidade dele, se é conhecida
  v_7d_toks  text;    -- (correção G6) as palavras do lugar dito
  v_7d_cli   text;    -- (correção G6) o nome do cliente da OS, e a cidade dele
  v_7d_forcado text;  -- (correção M5) o que veio depois de "lugar novo:"
  v_7d_sai_passou boolean := false;   -- (correção G11) a saída dita no passado
  -- FASE 7d: fim
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_planejar: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  -- A agenda desligada (agenda_config.modo_leitura) não anota: sem o *grava* ligado, o rascunho não teria saída.
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora: não anotei nada.', 'desligada');
  end if;
  if jsonb_typeof(d) <> 'object' then
    raise exception 'agenda_rascunho_planejar: p_dados tem de ser um objeto' using errcode = '22023';
  end if;
  -- FASE 5: prometido (a data como o dono disse ao cliente) e servico_cliente (como o cliente chama o serviço) saem de d
  -- antes da conferência dos campos; entram no rascunho no fim (v_out), conferidos.
  v_prom := nullif(btrim(coalesce(d ->> 'prometido', '')), '');
  v_serv := nullif(btrim(regexp_replace(coalesce(d ->> 'servico_cliente', ''), '\s+', ' ', 'g')), '');
  d := d - 'prometido' - 'servico_cliente';
  -- FASE 5: fim
  -- FASE 7b: (7b P2) a dupla (nao | todos | inicio | fim) e os meios-dias dela saem de d antes da conferência dos campos; entram no
  -- rascunho no fim (v_out), conferidos
  v_7b_dupla := nullif(lower(btrim(coalesce(d ->> 'dupla', ''))), '');
  v_7b_tem_meios := d ? 'dupla_meios' and jsonb_typeof(d -> 'dupla_meios') <> 'null';
  v_7b_meios_txt := d ->> 'dupla_meios';
  d := d - 'dupla' - 'dupla_meios';
  -- FASE 7b: fim
  select k into v_k from jsonb_object_keys(d) k where k <> all (c_campos) order by k limit 1;
  if v_k is not null then
    raise exception 'agenda_rascunho_planejar: o campo "%" não existe', v_k using errcode = '22023';
  end if;
  d := jsonb_strip_nulls(d);
  -- FASE 7d: (7d P7; §5.7) o que o dono desfaz do local e do bem sai de limpar aqui: a lista de antes e as frases dela ficam como estavam. Pôr e tirar a mesma coisa na mesma
  -- chamada é erro de quem chamou.
  if jsonb_typeof(d -> 'limpar') = 'array' then
    v_7d_limpar := array(select distinct x from jsonb_array_elements_text(d -> 'limpar') x where x = any (c_7d_limpar) order by 1);
    d := jsonb_set(d, '{limpar}', coalesce((select jsonb_agg(e) from jsonb_array_elements(d -> 'limpar') e where e #>> '{}' <> all (c_7d_limpar)), '[]'::jsonb));
    if ('local' = any (v_7d_limpar) and d ? 'local')
       or ('entrada' = any (v_7d_limpar) and d ? 'chega_em')
       or ('retirada' = any (v_7d_limpar) and d ? 'sai_em')
       or ('viagem' = any (v_7d_limpar) and d ? 'viagem')
       or ('autorizados' = any (v_7d_limpar) and d ? 'autorizados') then
      raise exception 'agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada' using errcode = '22023';
    end if;
  end if;
  -- FASE 7d: fim
  if d ? 'limpar' then
    if jsonb_typeof(d -> 'limpar') <> 'array' then
      raise exception 'agenda_rascunho_planejar: limpar tem de ser uma lista (espera, nao_antes, prazo ou escopo)' using errcode = '22023';
    end if;
    v_limpar := array(select distinct x from jsonb_array_elements_text(d -> 'limpar') x order by 1);
    select x into v_k from unnest(v_limpar) x where x <> all (c_limpar) order by 1 limit 1;
    if v_k is not null then
      raise exception 'agenda_rascunho_planejar: limpar "%" não existe (espera, nao_antes, prazo ou escopo)', v_k using errcode = '22023';
    end if;
    -- Pôr e tirar a mesma coisa na mesma chamada é erro de quem chamou.
    if ('espera' = any (v_limpar) and (d ? 'congelar_ate' or d ? 'revisar_em'))
       or ('nao_antes' = any (v_limpar) and (d ? 'nao_antes_de' or d ? 'nao_antes_motivo'))
       or ('prazo' = any (v_limpar) and d ? 'precisa_ate')
       or ('escopo' = any (v_limpar) and d ? 'escopo_em_aberto')
       or ('patio' = any (v_limpar) and d ? 'adiantavel_patio') then   -- FASE 2
      raise exception 'agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada' using errcode = '22023';
    end if;
  end if;
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que mudou nesse serviço.', 'sem_trecho');
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;

  -- Dias: o número dito (no trecho) ou "aceito a sua estimativa" (a sugestão, com fonte 'aceita').
  if d ? 'dias' then
    begin
      v_n := (d ->> 'dias')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n <= 0 or v_n > 60 or v_n * 2 <> trunc(v_n * 2) then
      return public._agenda_recusa('Quantos dias? Diga em dias ou meio dia (por exemplo, "2 dias" ou "um dia e meio").', 'dias_invalido');
    end if;
    if not public._agenda_trecho_tem_numero(p_trecho, v_n) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quantos dias.', public._agenda_dias(v_n)),
                                   'fora_do_trecho');
    end if;
    v_out := v_out || jsonb_build_object('dias', trim_scale(v_n), 'estimativa_fonte', 'dono');
  elsif coalesce((d ->> 'aceitar_sugestao')::boolean, false) then
    v_sug := public.os_duracao_sugerida(v_os);
    if coalesce((v_sug ->> 'sem_base')::boolean, false) or v_sug ->> 'sugerida' is null then
      return public._agenda_recusa('O orçamento não dá base para eu estimar: quantos dias?', 'sem_base');
    end if;
    v_out := v_out || jsonb_build_object('dias', (v_sug ->> 'sugerida')::numeric, 'estimativa_fonte', 'aceita');
  end if;

  -- Quem vai, por turno ("dia" quando não disse).
  if d ? 'com_quem' then
    if jsonb_typeof(d -> 'com_quem') <> 'array' then
      raise exception 'agenda_rascunho_planejar: com_quem tem de ser uma lista' using errcode = '22023';
    end if;
    for v_x in select e from jsonb_array_elements(d -> 'com_quem') with ordinality t(e, o) order by o loop
      if jsonb_typeof(v_x) = 'string' then
        v_x := jsonb_build_object('pessoa', v_x #>> '{}');
      end if;
      v_turnos := coalesce(nullif(btrim(v_x ->> 'turnos'), ''), 'dia');
      if v_turnos not in ('dia', 'manha', 'tarde') then
        raise exception 'agenda_rascunho_planejar: turnos "%" inválido (dia, manha ou tarde)', v_turnos using errcode = '22023';
      end if;
      v_rp := public.agenda_resolver_pessoa(v_x ->> 'pessoa', v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then
        return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
          coalesce((select jsonb_agg(e ->> 'nome' order by o)
                      from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      v_equipe := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_equipe) with ordinality t(e, o)
                             where e ->> 'payee_id' <> v_rp ->> 'payee_id'), '[]'::jsonb)
                  || jsonb_build_array(jsonb_build_object('payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
                                                          'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false),
                                                          'turnos', v_turnos));
    end loop;
    v_out := v_out || jsonb_build_object('equipe', v_equipe);
  end if;

  if d ? 'dono' then
    if d ->> 'dono' not in ('abre_e_fecha', 'sempre', 'nunca') then
      raise exception 'agenda_rascunho_planejar: dono "%" inválido (abre_e_fecha, sempre ou nunca)', d ->> 'dono' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('dono', d ->> 'dono');
  end if;

  if d ? 'precisa_ate' then
    v_dt := public._agenda_data_conferida(d ->> 'precisa_ate', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Até quando o cliente precisa?', btrim(d ->> 'precisa_ate')), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('precisa_ate', v_dt ->> 'ate');
  end if;

  -- O bem fora: "fora de 26 a 30/10", "fora até dia 3" (inclusive) ou "só fica livre dia 3" (livre nesse dia).
  if d ? 'bem_fora' then
    v_dt := public._agenda_data_conferida(d ->> 'bem_fora', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Até quando o bem fica fora?', btrim(d ->> 'bem_fora')), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('bem', jsonb_build_object(
      'modo', 'fora', 'de', greatest((v_dt ->> 'de')::date, p_hoje), 'ate', (v_dt ->> 'ate')::date,
      'livre_em', (v_dt ->> 'ate')::date + 1));
  end if;
  if d ? 'bem_livre_em' then
    v_dt := public._agenda_data_conferida(d ->> 'bem_livre_em', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_out := v_out || jsonb_build_object('bem', case
      when (v_dt ->> 'de')::date <= p_hoje then jsonb_build_object('modo', 'livre')
      else jsonb_build_object('modo', 'livre_em', 'de', p_hoje, 'ate', (v_dt ->> 'de')::date - 1, 'livre_em', (v_dt ->> 'de')::date) end);
  end if;

  if d ? 'nao_antes_de' then
    v_dt := public._agenda_data_conferida(d ->> 'nao_antes_de', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_out := v_out || jsonb_build_object('nao_antes_de', v_dt ->> 'de',
      'nao_antes_motivo', coalesce(left(nullif(btrim(d ->> 'nao_antes_motivo'), ''), 120), 'você disse'));
  elsif d ? 'nao_antes_motivo' then
    return public._agenda_recusa('Não antes de que dia?', 'sem_data');
  end if;

  if d ? 'escopo_em_aberto' then
    v_out := v_out || jsonb_build_object('escopo_em_aberto', nullif(left(btrim(d ->> 'escopo_em_aberto'), 160), ''));
  end if;
  if d ? 'escopo_decidido' then
    v_out := v_out || jsonb_build_object('escopo_decidido', nullif(left(btrim(d ->> 'escopo_decidido'), 160), ''));
    if not d ? 'escopo_em_aberto' then
      -- O que o dono decidiu fecha a pergunta em aberto.
      v_out := v_out || jsonb_build_object('escopo_em_aberto', null);
    end if;
  end if;

  if d ? 'congelar_ate' then
    v_dt := public._agenda_data_conferida(d ->> 'congelar_ate', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if d ? 'revisar_em' then
      v_dt2 := public._agenda_data_conferida(d ->> 'revisar_em', p_trecho, p_hoje, 'futuro');
      if not (v_dt2 ->> 'ok')::boolean then return v_dt2; end if;
    else
      v_dt2 := v_dt;   -- sem data para rever: revê no dia em que a espera acaba
    end if;
    v_out := v_out || jsonb_build_object('congelada_ate', v_dt ->> 'ate', 'revisar_em', v_dt2 ->> 'de');
  elsif d ? 'revisar_em' then
    return public._agenda_recusa('Em espera até quando?', 'sem_data');
  end if;

  if d ? 'prioridade' then
    begin
      v_n := (d ->> 'prioridade')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n not in (1, 2, 3) then
      raise exception 'agenda_rascunho_planejar: prioridade "%" inválida (1, 2 ou 3)', d ->> 'prioridade' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('prioridade', v_n::int);
  end if;

  if d ? 'sem_material' then
    v_out := v_out || jsonb_build_object('sem_material', (d ->> 'sem_material')::boolean);
  end if;

  -- FASE 2: quanto do serviço dá para adiantar no pátio sem o bem — o número tem de estar no que o dono disse e não
  -- passa dos dias do serviço (os ditos agora, ou os que já estavam).
  if d ? 'adiantavel_patio' then
    begin
      v_n := (d ->> 'adiantavel_patio')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n <= 0 or v_n > 60 or v_n * 2 <> trunc(v_n * 2) then
      return public._agenda_recusa('Quanto dá para adiantar no pátio? Diga em dias ou meio dia (por exemplo, "um dia").', 'patio_invalido');
    end if;
    if not public._agenda_trecho_tem_numero(p_trecho, v_n) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quanto dá para adiantar no pátio.',
                                          public._agenda_dias(v_n)), 'fora_do_trecho');
    end if;
    v_dias_os := coalesce((v_out ->> 'dias')::numeric,
                          (select pl.dias from public.os_planejamento pl where pl.service_order_id = v_os));
    if v_dias_os is not null and v_n > v_dias_os then
      return public._agenda_recusa(format('O serviço todo é de %s: no pátio dá para adiantar no máximo isso. Quanto dá?',
                                          public._agenda_dias(v_dias_os)), 'patio_maior');
    end if;
    v_out := v_out || jsonb_build_object('adiantavel_patio', trim_scale(v_n));
  end if;

  -- O que o dono desfez: o campo vai como nulo (o *grava* grava vazio; a correção na mesma releitura também apaga).
  if 'espera' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('congelada_ate', null, 'revisar_em', null);
  end if;
  if 'nao_antes' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('nao_antes_de', null, 'nao_antes_motivo', null);
  end if;
  if 'prazo' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('precisa_ate', null);
  end if;
  if 'escopo' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('escopo_em_aberto', null);
  end if;
  if 'patio' = any (v_limpar) then   -- FASE 2
    v_out := v_out || jsonb_build_object('adiantavel_patio', null);
  end if;

  -- FASE 5: o que o dono disse ao cliente: a data conferida no trecho e entendida pelo banco (agenda_data_dita: "dia 3" é
  -- firme; "entre 4 e 8/11" e "semana que vem" são faixa), nunca no passado; o serviço como o cliente diz (3 a c_serv_max
  -- caracteres, sem valor, pagamento, número de OS nem link).
  if v_prom is not null then
    v_dtp := public._agenda_data_conferida(v_prom, p_trecho, p_hoje, 'futuro');
    if not (v_dtp ->> 'ok')::boolean then return v_dtp; end if;
    if (v_dtp ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Que dia você disse ao cliente?', v_prom), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('prometido', jsonb_build_object(
      'tipo', case when v_dtp ->> 'de' = v_dtp ->> 'ate' then 'firme' else 'faixa' end,
      'de', v_dtp ->> 'de', 'ate', v_dtp ->> 'ate', 'dito', left(v_prom, 60)));
  end if;
  if v_serv is not null then
    if char_length(v_serv) < 3 or char_length(v_serv) > c_serv_max then
      return public._agenda_recusa(format('Diga em poucas palavras como o cliente chama o serviço (até %s letras), por exemplo "a instalação do compressor".',
                                          c_serv_max), 'servico_longo');
    end if;
    if public._agenda_cliente_texto_proibido(v_serv) is not null then
      return public._agenda_recusa('Como o cliente chama o serviço não leva valor, pagamento, número de OS nem link: diga só o serviço ("a troca das baterias").',
                                   'servico_proibido');
    end if;
    v_out := v_out || jsonb_build_object('servico_cliente', v_serv);
  end if;
  -- FASE 5: fim
  -- FASE 7b: (7b P2; R4.3(b), §6.6) a dupla dita: nao = 1 pessoa (sem a inferência); todos = o tempo todo; inicio/fim = nos
  -- dupla_meios primeiros ou últimos meios-dias (1 a 20, no trecho; "no primeiro dia" = 2 meios-dias, com "dia" no trecho). Com
  -- modo_dupla desligado, inicio/fim é recusado (a 7a não enxerga a dupla numa parte: o motor mandaria 1 pessoa num serviço de
  -- segurança e a releitura teria prometido a dupla); todos e nao valem em todo modo, como a palavra da 7a. Com menos técnicos
  -- na grade do que a dupla pede, a releitura avisa que a OS espera (a classe dupla de _agenda_classe_da_os).
  if v_7b_dupla is not null or v_7b_tem_meios then
    if v_7b_dupla is null or v_7b_dupla not in ('nao', 'todos', 'inicio', 'fim') then
      raise exception 'agenda_rascunho_planejar: dupla "%" inválida (nao, todos, inicio ou fim)', coalesce(v_7b_dupla, '')
        using errcode = '22023';
    end if;
    if v_7b_dupla in ('inicio', 'fim') then
      if (public._agenda_cfg()).modo_dupla = 'desligado' then
        return public._agenda_recusa(format('A dupla só numa parte do serviço ainda não está ligada. Diga *%s com dupla* (o tempo todo) ou ''vai com um só''.',
                                            v_ro ->> 'cliente_curto'), 'dupla_parte_desligada');
      end if;
      begin
        v_7b_meios := v_7b_meios_txt::int;
      exception when others then
        v_7b_meios := null;
      end;
      if v_7b_meios is null or v_7b_meios < 1 or v_7b_meios > 20 then
        return public._agenda_recusa('Em quantos meios-dias vai a dupla? (por exemplo, "dois no primeiro dia" = 2 meios-dias)', 'dupla_meios');
      end if;
      if not (public._agenda_trecho_tem_numero(p_trecho, v_7b_meios)
              or (public._agenda_normal(p_trecho) ~ '\mdias?\M'
                  and (v_7b_meios = 2 or (v_7b_meios % 2 = 0 and public._agenda_trecho_tem_numero(p_trecho, v_7b_meios / 2))))) then
        return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo em quantos meios-dias vai a dupla.', v_7b_meios),
                                     'fora_do_trecho');
      end if;
    elsif v_7b_tem_meios then
      raise exception 'agenda_rascunho_planejar: dupla_meios só com dupla inicio ou fim' using errcode = '22023';
    end if;
    if v_7b_dupla <> 'nao' then
      v_7b_tec := public._agenda_tecnicos_da_grade(p_hoje);
      if cardinality(v_7b_tec) < greatest((public._agenda_cfg()).equipe_sugerida, 2) then
        v_7b_aviso := format('Hoje %s: até você chamar alguém e me dizer os dias, eu não marco %s',
                             public._agenda_tecnicos_frase(v_7b_tec), v_ro ->> 'cliente_curto');
      end if;
    end if;
    v_out := v_out || jsonb_build_object('dupla', v_7b_dupla, 'dupla_meios', v_7b_meios, 'dupla_aviso', v_7b_aviso);
  end if;
  -- FASE 7b: fim
  -- FASE 7d: (7d P7; §5.7) o que o dono disse do local e do bem. O local e as pessoas pelo banco (ambíguo ou não achado = a pergunta, nada no rascunho); as datas conferidas no
  -- trecho e entendidas por agenda_data_dita (a chegada e a saída, o de da faixa); o resto, as listas fechadas. Vale em todo modo: ele é a fonte, e quem lê está atrás de _agenda_local_modo.
  if d ? 'local' then
    -- (correção M5) "lugar novo: X" passa por cima de tudo que recusa e de tudo que pergunta: sem a decisão do resolver, direto ao ramo do lugar novo. Com o cadastro vazio, segue recusando (T5)
    v_7d_forcado := public._agenda_local_forcado(d ->> 'local');
    if v_7d_forcado is not null then
      v_7d_rl := jsonb_build_object('status', 'nao_achei', 'texto', format('Não achei "%s" no cadastro.', v_7d_forcado));
    else
      v_7d_rl := public.agenda_resolver_local(d ->> 'local', p_hoje);
      -- (correção G6) "na casa do Nelson", na OS do Nelson, é a casa do cliente. A casa de outro nome é um lugar como os outros
      v_7d_toks := array_to_string(public._agenda_local_palavras(d ->> 'local'), ' ');
      v_7d_cli := public._agenda_normal(normalize(coalesce(v_ro ->> 'cliente_curto', ''), nfc));
      if v_7d_cli <> '' and (v_7d_toks = 'casa ' || v_7d_cli or v_7d_toks like 'casa ' || v_7d_cli || ' %') then
        v_7d_rl := jsonb_build_object('status', 'casa_cliente');
      end if;
    end if;
    if v_7d_rl ->> 'status' = 'casa_cliente' then
      -- (correção G6) a cidade dita junto ("na casa dele em Porto Belo") não se perde: a linha da casa sem cidade leva essa, e o cliente não muda. Se o cliente tem cidade, vale a dele, e a releitura mostra qual
      v_7d_mun := public._agenda_municipio_conhecido(d ->> 'local', v_os);
      if v_7d_mun ->> 'municipio' is not null then
        -- (correção M10) "N/D", "." e "-" contam como sem cidade: vale a que o dono disse
        select case when upper(btrim(coalesce(cl.city, ''))) not in ('', 'N/D', '.', '-') then btrim(cl.city) end into v_7d_txt
          from public.service_orders so join public.clients cl on cl.id = so.client_id
         where so.id = v_os and position(chr(65533) in coalesce(cl.city, '')) = 0;
      end if;
      v_out := v_out || jsonb_build_object('local_id', null, 'local_nome', null, 'local_casa', true, 'local_novo', null,
                                           'local_casa_em', coalesce(v_7d_txt, v_7d_mun ->> 'municipio'),
                                           'local_casa_uf', case when v_7d_txt is null then v_7d_mun ->> 'uf' end,
                                           'local_casa_dita', v_7d_txt is null and v_7d_mun ->> 'municipio' is not null,
                                           -- (correção A1) o rascunho junta as frases: a casa não herda a cidade do lugar novo dito antes, e os outros ramos zeram a da casa
                                           'local_municipio', null, 'local_uf', null);
    elsif v_7d_rl ->> 'status' = 'ok' then
      v_out := v_out || jsonb_build_object('local_id', v_7d_rl ->> 'id', 'local_nome', v_7d_rl ->> 'nome', 'local_casa', false, 'local_novo', null,
                                           'local_casa_em', null, 'local_casa_uf', null, 'local_casa_dita', false);
    -- (correção O2) o lugar fora do cadastro: se o texto é um nome plausível, entra; o *grava* cria a linha (só o dono passa por aqui: o M11 só pergunta). A cidade só se é conhecida
    -- (correção T5) com o cadastro vazio (entre as funções de borda e o dado), recusa como antes: "Marina Itajaí" viraria uma linha falsa, e a semente, uma segunda
    elsif v_7d_rl ->> 'status' = 'nao_achei' and exists (select 1 from public.agenda_locais x where x.ativo and x.tipo <> 'casa_cliente') then
      v_7d_novo := public._agenda_local_novo(d ->> 'local');
      if not (v_7d_novo ->> 'ok')::boolean then
        return public._agenda_recusa(v_7d_novo ->> 'texto', 'local_' || (v_7d_novo ->> 'motivo'));
      end if;
      v_7d_mun := public._agenda_municipio_conhecido(v_7d_novo ->> 'nome', v_os);
      v_out := v_out || jsonb_build_object('local_id', null, 'local_nome', v_7d_novo ->> 'nome', 'local_casa', false, 'local_novo', v_7d_novo ->> 'nome',
                                           'local_municipio', v_7d_mun ->> 'municipio',
                                           -- (correção M3) a UF da base sem município conhecido não diz viagem: "Cabeçudas, SC" é da região, como sem a UF. A de fora diz (pernoite)
                                           'local_uf', case when v_7d_mun ->> 'municipio' is null and v_7d_novo ->> 'uf' = any ((public._agenda_cfg()).viagem_uf_bate_volta) then null
                                                            else coalesce(v_7d_novo ->> 'uf', v_7d_mun ->> 'uf') end,
                                           'local_casa_em', null, 'local_casa_uf', null, 'local_casa_dita', false);
    else
      -- (correção M5) "Qual deles" sem a opção "outro lugar em" não tinha saída: só nesta recusa, a frase das outras. O texto do resolver não muda: ele tem outros leitores
      return public._agenda_recusa(v_7d_rl ->> 'texto' || case when v_7d_rl ->> 'status' = 'ambiguo' and position('outro lugar em' in v_7d_rl ->> 'texto') = 0
                                                               then format(' Se é mesmo um lugar, diga "lugar novo: %s".', btrim(d ->> 'local')) else '' end,
        'local_' || (v_7d_rl ->> 'status'),
        coalesce((select jsonb_agg(e ->> 'nome' order by o) from jsonb_array_elements(v_7d_rl -> 'opcoes') with ordinality t(e, o)), '[]'::jsonb));
    end if;
  end if;
  if d ? 'bem_onde' then
    if d ->> 'bem_onde' not in ('agua', 'seco', 'garagem_seca', 'patio', 'com_cliente') then
      raise exception 'agenda_rascunho_planejar: bem_onde "%" inválido (agua, seco, garagem_seca, patio ou com_cliente)', d ->> 'bem_onde' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('bem_situacao', d ->> 'bem_onde');
  end if;
  if d ? 'bem_exige' then
    if d ->> 'bem_exige' not in ('agua', 'seco', 'tanto_faz') then
      raise exception 'agenda_rascunho_planejar: bem_exige "%" inválido (agua, seco ou tanto_faz)', d ->> 'bem_exige' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('bem_exige', d ->> 'bem_exige');
  end if;
  if d ? 'descer_quem' then
    v_7d_txt := btrim(regexp_replace(d ->> 'descer_quem', '\s+', ' ', 'g'));
    if char_length(v_7d_txt) not between c_7d_quem_min and c_7d_quem_max then
      return public._agenda_recusa('Quem desce o barco? Diga em poucas palavras, por exemplo "a marina".', 'descer_quem');
    end if;
    v_out := v_out || jsonb_build_object('descer_quem', v_7d_txt);
  end if;
  -- "até dia 13" é uma faixa que começa hoje: o de seria um dia que ninguém disse
  if d ? 'chega_em' then
    v_dt := public._agenda_data_conferida(d ->> 'chega_em', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    -- (correção O7a) verbo no passado com a data sem mês: já aconteceu. "chegou dia 5", dito em 06/11, é 05/11, não 05/12; "dia 20" é 20/10. agenda_data_dita não muda: quem chama pede o sentido
    -- (correção T7, G10) o verbo só vale na oração da data: _agenda_data_no_passado
    if public._agenda_data_sem_mes(d ->> 'chega_em') and (v_dt ->> 'de')::date > p_hoje
       and public._agenda_data_no_passado(p_trecho, d ->> 'chega_em', 'chega') then
      v_dt := public._agenda_data_conferida(d ->> 'chega_em', p_trecho, p_hoje, 'passado');
      if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    end if;
    if (v_dt ->> 'de')::date = p_hoje and (v_dt ->> 'ate')::date > p_hoje then
      return public._agenda_recusa('Que dia chega? Diga um dia só (por exemplo, "dia 13").', 'data_faixa');
    end if;
    v_out := v_out || jsonb_build_object('entrada_em', v_dt ->> 'de');
  end if;
  if d ? 'sai_em' then
    v_dt := public._agenda_data_conferida(d ->> 'sai_em', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    -- (correção G11) a saída no passado segue a regra da chegada: "saiu dia 5", dito em 06/11, é 05/11
    if public._agenda_data_sem_mes(d ->> 'sai_em') and (v_dt ->> 'de')::date > p_hoje
       and public._agenda_data_no_passado(p_trecho, d ->> 'sai_em', 'sai') then
      v_7d_sai_passou := true;
      v_dt := public._agenda_data_conferida(d ->> 'sai_em', p_trecho, p_hoje, 'passado');
      if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    end if;
    if (v_dt ->> 'de')::date = p_hoje and (v_dt ->> 'ate')::date > p_hoje then
      return public._agenda_recusa('Que dia sai? Diga um dia só (por exemplo, "dia 13").', 'data_faixa');
    end if;
    v_out := v_out || jsonb_build_object('retirada_em', v_dt ->> 'de');
    -- (correção O7b) a chegada sem mês depois da saída dita na mesma frase: "chega dia 5 e ele busca dia 13", dito em 06/11, é 05/11 e 13/11. A chegada cai no mês da saída ou no anterior,
    -- se assim ficar antes dela. A releitura mostra as 2 datas por extenso antes do *grava*.
    -- (correção G10) sem verbo no passado a chegada não volta mais de 7 dias: "chega dia 20 e sai dia 10", dito em 06/11, é 20/11 e 10/12: quem anda é a saída sem mês, para depois da chegada
    if d ? 'chega_em' and public._agenda_data_sem_mes(d ->> 'chega_em')
       and (v_out ->> 'entrada_em')::date >= (v_out ->> 'retirada_em')::date then
      v_7d_ent := public._agenda_data_um(public._agenda_preparar_data(d ->> 'chega_em'), p_hoje, 'futuro', true, (v_out ->> 'retirada_em')::date - 1, null);
      if v_7d_ent is not null and v_7d_ent < (v_out ->> 'retirada_em')::date and v_7d_ent >= p_hoje - c_7d_volta then
        v_out := v_out || jsonb_build_object('entrada_em', v_7d_ent);
      elsif public._agenda_data_sem_mes(d ->> 'sai_em') and not v_7d_sai_passou then
        v_7d_sai := public._agenda_data_um(public._agenda_preparar_data(d ->> 'sai_em'), p_hoje, 'futuro', false, null, (v_out ->> 'entrada_em')::date + 1);
        if v_7d_sai is not null then
          v_out := v_out || jsonb_build_object('retirada_em', v_7d_sai);
        end if;
      end if;
    end if;
  end if;
  if d ? 'viagem' then
    if d ->> 'viagem' not in ('regional', 'bate_volta', 'pernoite') then
      raise exception 'agenda_rascunho_planejar: viagem "%" inválida (regional, bate_volta ou pernoite)', d ->> 'viagem' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('viagem', d ->> 'viagem');
  end if;
  if d ? 'autorizados' then
    if jsonb_typeof(d -> 'autorizados') <> 'array' or jsonb_array_length(d -> 'autorizados') = 0 then
      raise exception 'agenda_rascunho_planejar: autorizados tem de ser a lista de nomes' using errcode = '22023';
    end if;
    for v_x in select e from jsonb_array_elements(d -> 'autorizados') with ordinality t(e, o) order by o loop
      v_rp := public.agenda_resolver_pessoa(v_x #>> '{}', v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then
        return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
          coalesce((select jsonb_agg(e ->> 'nome' order by o)
                      from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      -- a mesma pessoa dita 2 vezes fica uma, na posição da última (a régua de com_quem)
      v_7d_aut := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_7d_aut) with ordinality t(e, o)
                             where e ->> 'payee_id' <> v_rp ->> 'payee_id'), '[]'::jsonb)
                  || jsonb_build_array(jsonb_build_object('payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
                                                          'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false))
                                       -- (correção O16) a chave só para quem saiu da equipe
                                       || case when public._agenda_saiu_da_equipe((v_rp ->> 'payee_id')::uuid) then jsonb_build_object('saiu', true) else '{}'::jsonb end);
    end loop;
    v_out := v_out || jsonb_build_object('autorizados', v_7d_aut);
  end if;
  if 'local' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('local_id', null, 'local_nome', null, 'local_casa', false, 'local_novo', null,
                                         'local_casa_em', null, 'local_casa_uf', null, 'local_casa_dita', false);   -- (correção A1)
  end if;
  if 'entrada' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('entrada_em', null);
  end if;
  if 'retirada' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('retirada_em', null);
  end if;
  if 'viagem' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('viagem', null);
  end if;
  if 'autorizados' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('autorizados', '[]'::jsonb);
  end if;
  -- A chegada antes da saída, contra o que já está no rascunho aberto e na OS (o CHECK entrada_antes_saida recusaria no *grava*, sem dizer por quê)
  if v_out ?| array['entrada_em', 'retirada_em'] then
    select r.dados into v_7d_velho from public.agenda_rascunho r
     where r.autor = v_autor and r.chave = 'planejar:' || v_os::text and r.estado = 'aberto' and r.expira_em > now();
    v_7d_velho := coalesce(v_7d_velho, '{}'::jsonb);
    select case when v_out ? 'entrada_em' then (v_out ->> 'entrada_em')::date
                when v_7d_velho ? 'entrada_em' then (v_7d_velho ->> 'entrada_em')::date else x.entrada_em end,
           case when v_out ? 'retirada_em' then (v_out ->> 'retirada_em')::date
                when v_7d_velho ? 'retirada_em' then (v_7d_velho ->> 'retirada_em')::date else x.retirada_em end
      into v_7d_ent, v_7d_sai
      from (select 1) u left join public.os_planejamento x on x.service_order_id = v_os;
    if v_7d_ent >= v_7d_sai then
      return public._agenda_recusa(format('Não anotei: a saída (%s) tem de ser depois da chegada (%s). Me diga as datas certas.',
                                          public._dia_curto(v_7d_sai), public._dia_curto(v_7d_ent)), 'chega_depois_de_sai');
    end if;
  end if;
  -- FASE 7d: fim
  if v_out = '{}'::jsonb then
    return public._agenda_recusa('O que mudou nesse serviço? (quantos dias, quem vai, até quando o cliente precisa…)', 'nada');
  end if;

  select case when public._agenda_normal(coalesce(vs.asset_type, vs.name)) ~ 'motorhome|motor home|trailer'
              then 'o motorhome' else 'o barco' end
    into v_bem
    from public.service_orders so left join public.vessels vs on vs.id = so.vessel_id
   where so.id = v_os;

  -- FASE 7d: (correção O17, C8) em teste, a releitura diz a verdade: viagem, pátio e acesso ficam anotados, e o plano só muda quando o assunto for ligado. Uma chave por assunto, porque o
  -- rascunho junta as frases da mesma OS; só com o assunto dito, e ausente com o modo ligado. Pelo freio também: _agenda_local_modo.
  if (v_out ->> 'entrada_em' is not null or v_out ->> 'retirada_em' is not null) and public._agenda_local_modo('patio') <> 'ligado' then
    v_out := v_out || jsonb_build_object('em_teste_patio', true);
  end if;
  if v_out ->> 'viagem' is not null and public._agenda_local_modo('viagem') <> 'ligado' then
    v_out := v_out || jsonb_build_object('em_teste_viagem', true);
  end if;
  if jsonb_array_length(coalesce(v_out -> 'autorizados', '[]'::jsonb)) > 0 and public._agenda_local_modo('acesso') <> 'ligado' then
    v_out := v_out || jsonb_build_object('em_teste_acesso', true);
  end if;
  -- FASE 7d: fim
  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'planejar', 'planejar:' || v_os::text, v_os,
                                          public._agenda_os_do_rascunho(v_ro) || jsonb_build_object('bem_nome', v_bem) || v_out,
                                          p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

-- ── A porta da nova ─────────────────────────────────────────────────────────────────────────
-- Interna, como _agenda_local_novo: quem a chama é definer.
revoke all on function public._agenda_local_forcado(text) from public, anon, authenticated, service_role;
