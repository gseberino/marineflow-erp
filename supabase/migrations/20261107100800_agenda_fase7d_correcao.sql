-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), correção da revisão, Onda 1: "saber onde é e não cobrar errado".
-- Ordem de serviço: decisoes-do-fio.md, seção Onda 1 (vale sobre a spec, sobre o R6 e sobre as notas). Achados: f7d/rev-objetivo (O), f7d/rev-conformidade (C), f7d/rev-regressao (R).
-- Notas: notas-fase7d.md, seção "Correção, Onda 1". Depende de 20261107100000 a 20261107100700. Vem antes da semente 20261107100900.
--
-- ═══ ESTRUTURA E FUNÇÕES — OK NOMEADO ═══ (2 colunas em agenda_locais, 1 índice; funções novas e recriadas; nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7d/corr1/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (a regra do "mais nova" é conferida na
-- montagem). Nas que vêm de antes da 7d, só blocos "-- FASE 7d: (correção …)" inseridos: tirados os blocos, é a origem, byte a byte. Nas que nasceram na 7d, a correção troca linhas.
--
-- O QUE MUDA, por achado:
--   O1  *agenda locais*: todas as OS abertas, uma linha curta por OS, pela cadeia; primeiro as supostas; no teto cortam as notas, as ditas e por último as supostas, com "(e mais N)".
--   O2  o lugar fora do cadastro entra pelo *grava* (tipo outro, conferido_por nulo). municipio passa a aceitar nulo: cidade desconhecida. A preposição do tipo outro é "em".
--   O3  "na casa do cliente" vira local de verdade: 1 linha por cliente (client_id). Sai o trecho.
--   O4  serviço começado não é cobrado do que vem antes dele (_agenda_combinar_da_os, o sinal plano_comecou do P6).
--   O5  "eu te aviso" passa a ser verdade: _agenda_local_avisar_acesso, pelo caminho da ficha (_agenda_equipe_registrar, tipo resposta), na janela da ficha, uma vez por pessoa e dia.
--   O6  autorizados com local suposto: local_id nulo = desta OS.
--   O7  chegada sem mês: verbo no passado e chegada depois da saída dita na mesma frase. agenda_data_dita não muda.
--   O10 vaga, descida e entrada nascem como o acesso: ate <= hoje.
--   O14 viagem dita com local suposto: lugar desconhecido para o calendário; a pernoite sem encaixe diz o motivo.
--   O15 o feriado do município diz o motivo como o nacional.
--   O18 a releitura da crítica diz qual é.
--   O19 o exemplo da pergunta local é lugar, não data; quem disse data e não lugar: a pergunta diz que ele respondeu sem dizer onde.
--   O21 bem_livre fecha quando o dono diz onde o bem está, ou que está livre.
--   C1  rede K no calendário: acima de gestor_k_os (ou dos dias avisados), UMA chamada com o array todo. _agenda_gestor_onda_conta conhece o motivo local.
--   C2  parar o M11 (onde_fica_desde nula) recusa o que está na fila.
--   C9  a recomendação de tirar o apelido (§11) no foco.
--   R3  a resposta ao M11 que não fala de lugar não vira acesso; o "sim" atrasado do M1 vai ao M1.
--   R4  "Sim, na Marina Itajaí": o acordo entra no leitor do texto inteiro, só com M11 pendente.
--   R5  o M11 em teste nasce contado.
--   R6  a rodada do local: isola por OS; com erro tenta de novo, até 3 vezes por dia; depois, app_error_logs.
--   C7  é da semente (20261107100900): rodar de novo depois do DESFAZER reativa os locais.
--
-- SOMBRA: com os 6 modos em sombra ou desligados, o motor, a vigia e o fechamento ficam byte a byte (o M1 e o M1c de agenda_fase7d_motor.sql e o C8j de agenda_fase7d_combinar.sql). O que muda
-- sem modo (a conversa do dono e o foco *agenda locais*) está na lista "entra sem modo" das notas.
--
-- PROVA: supabase/tests/agenda_fase7d_correcao.sql.
--
-- DESFAZER: reaplicar as definições de 20261107100000 a 20261107100700 das funções recriadas aqui, apagar as novas e:
--   drop index if exists public.agenda_locais_uma_casa_por_cliente;
--   alter table public.agenda_locais drop constraint if exists local_cliente_so_na_casa, drop column if exists client_id;
--   (municipio volta a not null só depois de tirar ou preencher as linhas sem cidade)

-- ── A estrutura: o lugar sem cidade e a casa por cliente ───────────────────────────────────
-- (O2) "cidade e UF só quando o texto casa com município conhecido; senão nulas, e feriado e viagem tratam como cidade desconhecida"
alter table public.agenda_locais alter column municipio drop not null;
-- (O3) o menor formato: a chave da linha por cliente. Fora de casa_cliente, nula.
alter table public.agenda_locais add column if not exists client_id uuid references public.clients(id) on delete set null;
alter table public.agenda_locais drop constraint if exists local_cliente_so_na_casa;
alter table public.agenda_locais add constraint local_cliente_so_na_casa check (client_id is null or tipo = 'casa_cliente');
create unique index if not exists agenda_locais_uma_casa_por_cliente on public.agenda_locais (client_id) where tipo = 'casa_cliente' and client_id is not null;
comment on column public.agenda_locais.client_id is 'Agenda de Produção (Fase 7d, correção O3): de quem é a casa, no tipo casa_cliente; uma linha por cliente. Nula nos outros tipos.';
comment on column public.agenda_locais.municipio is 'Agenda de Produção (Fase 7d; correção O2): a cidade. Nula no lugar novo que o dono disse e que não casa com município conhecido: feriado e viagem tratam como cidade desconhecida.';

-- ── As novas ───────────────────────────────────────────────────────────────────────────────
-- (O7) A data dita não tem mês? "dia 5", "5", "terça". Sem barra e sem o relativo ("amanhã", "daqui a 3 dias"), que já diz o dia.
create or replace function public._agenda_data_sem_mes(p_dito text)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  select s !~ '/' and s ~ '(^(?:(?:o|no|na|em|pro|pra|para) )?\d{1,2}$|\mdia \d{1,2}\M|\m(segunda|terca|quarta|quinta|sexta|sabado|domingo)\M)'
    from (select public._agenda_preparar_data(coalesce(p_dito, '')) as s) x;
$function$;

-- (O2) O nome de um lugar novo, como o dono disse, com a caixa arrumada; ou a recusa que explica. Não lê nada: quem decide se o lugar existe é agenda_resolver_local.
create or replace function public._agenda_local_novo(p_ref text)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  c_max       constant int := 60;       -- decisão do fio (O2): acima disso não é nome
  c_generico  constant text[] := array['cliente', 'ele', 'ela', 'dele', 'dela', 'casa', 'servico', 'bem', 'barco', 'motorhome', 'nao', 'sei', 'ninguem', 'nenhum', 'qualquer', 'algum', 'alguma',
                                        'outro', 'outra', 'cidade', 'mesmo', 'mesma', 'onde', 'ainda'];
  c_exemplo   constant text := 'me diga o nome do lugar (por exemplo, "Nova Trento").';
  v_t    text := btrim(regexp_replace(coalesce(p_ref, ''), '\s+', ' ', 'g'));
  v_n    text;
  v_nome text;
begin
  -- O que veio junto do nome: "é em", "fica no", "outro lugar em"
  v_t := regexp_replace(v_t, '^((é|fica|ficou|está|tá|lá)\s+)*(outr[oa]\s+(lugar|local|ponto|endereço)\s+)?((em|no|na|nos|nas)\s+)?', '', 'i');
  v_t := btrim(regexp_replace(v_t, '[.,;:!?]+$', ''));
  v_n := public._agenda_normal(normalize(v_t, nfc));

  if v_n !~ '[a-z]{2}' then
    if v_n ~ '\d' then
      return jsonb_build_object('ok', false, 'motivo', 'data', 'texto', format('"%s" não é um lugar: %s', btrim(p_ref), c_exemplo));
    end if;
    return jsonb_build_object('ok', false, 'motivo', 'vazio', 'texto', 'Diga qual local: o nome da marina ou do estaleiro, ou "pátio".');
  end if;
  if public._agenda_preparar_data(v_t) ~ '\mdia \d{1,2}\M' or v_n ~ '\m\d{1,2}/\d{1,2}'
     or v_n ~ '\m(segunda|terca|quarta|quinta|sexta|sabado|domingo|amanha|hoje|ontem)\M' then
    return jsonb_build_object('ok', false, 'motivo', 'data', 'texto', format('"%s" parece uma data, não um lugar: %s', btrim(p_ref), c_exemplo));
  end if;
  if char_length(v_t) > c_max then
    return jsonb_build_object('ok', false, 'motivo', 'longo', 'texto', format('Esse nome passa de %s letras: %s', c_max, c_exemplo));
  end if;
  if not exists (select 1 from unnest(public._agenda_local_palavras(v_t)) w where w <> all (c_generico)) then
    return jsonb_build_object('ok', false, 'motivo', 'vazio', 'texto', format('Não entendi o lugar: %s', c_exemplo));
  end if;

  -- A caixa: a 1ª de cada palavra, "de" e "do" em minúscula, a sigla como veio. Tudo em maiúscula é grito, não sigla.
  v_nome := array_to_string(array(
    select case when o > 1 and lower(w) = any (array['de', 'do', 'da', 'dos', 'das', 'e', 'em']) then lower(w)
                when w = upper(w) and w <> lower(w) and char_length(w) <= 3 and v_t <> upper(v_t) then w
                else public._agenda_maiuscula(lower(w)) end
      from unnest(string_to_array(v_t, ' ')) with ordinality u(w, o) order by o), ' ');
  return jsonb_build_object('ok', true, 'nome', v_nome);
end;
$function$;

-- (O2) O município do lugar novo, se é conhecido: o mesmo caminho da cidade do cliente na cadeia (_agenda_normal sobre o nfc, sem o caractere quebrado, a UF de 2 letras). Conhecido = a cidade do
-- cliente da OS, um município da região, a cidade de um local, ou a cidade de algum cliente. Também vale o fim do nome ("Marina do João em Porto Belo"). Senão, nulos.
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
begin
  v_cand := array_remove(array[p_nome, (regexp_match(p_nome, '\sem\s+(.+)$', 'i'))[1]], null);
  foreach v_n in array v_cand loop
    v_n := public._agenda_normal(normalize(v_n, nfc));
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
      select coalesce(v_mun, x.cidade), x.uf into v_mun, v_uf
        from (select btrim(cl.city) as cidade, upper(btrim(coalesce(cl.state, ''))) as uf, count(*) as n
                from public.clients cl
               where cl.city is not null and position(chr(65533) in cl.city) = 0
                 and public._agenda_normal(normalize(cl.city, nfc)) = v_n
               group by 1, 2
               order by (upper(btrim(coalesce(cl.state, ''))) ~ '^[A-Z]{2}$') desc, count(*) desc, 1, 2
               limit 1) x;
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

-- (O2) Acha ou cria a linha do lugar novo, no *grava*. Só _agenda_aplicar_planejar chama: só o dono cria. Tipo outro, sem conferir (conferido_por nulo). A linha que o *desfaz* tirou volta.
create or replace function public._agenda_local_criar(p_nome text, p_municipio text, p_uf text, p_autor uuid)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  l  public.agenda_locais;
  v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext('agenda_local_criar'));
  select * into l from public.agenda_locais x
   where x.tipo <> 'casa_cliente' and public._agenda_normal(normalize(x.nome, nfc)) = public._agenda_normal(normalize(p_nome, nfc))
   order by x.ativo desc, x.criado_em limit 1;
  if l.id is not null then
    if l.ativo then
      return jsonb_build_object('id', l.id, 'nome', l.nome, 'criada', false);
    end if;
    update public.agenda_locais x set ativo = true, atualizado_por = p_autor where x.id = l.id;
    return jsonb_build_object('id', l.id, 'nome', l.nome, 'criada', true);
  end if;
  insert into public.agenda_locais (nome, tipo, municipio, uf, atualizado_por)
  values (p_nome, 'outro', p_municipio, p_uf, p_autor)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'nome', p_nome, 'criada', true);
end;
$function$;

-- (O3) Acha ou cria a linha da casa do cliente da OS: tipo casa_cliente, "casa de {nome curto}", a cidade e a UF dele quando servem. Uma por cliente.
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
  v_mun := case when char_length(v_mun) between 2 and 60 and position(chr(65533) in v_mun) = 0 then v_mun end;
  v_uf := upper(btrim(coalesce(cl.state, '')));
  v_uf := case when v_uf ~ '^[A-Z]{2}$' and v_mun is not null then v_uf end;
  v_nome := left('casa de ' || public._agenda_nome_curto(cl.name), 80);
  insert into public.agenda_locais (nome, tipo, municipio, uf, client_id, atualizado_por)
  values (v_nome, 'casa_cliente', v_mun, v_uf, cl.id, p_autor)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'nome', v_nome, 'criada', true);
end;
$function$;

-- (O15) O feriado do município que o bloco atravessa, para o texto do item: "ter 20 é feriado em Balneário Camboriú". p_txt é o local_txt da fila (índice do dia → motivo da máscara).
create or replace function public._agenda_feriado_do_bloco(p_txt jsonb, p_d_ini date, p_de date, p_ate date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select nullif(array_to_string(array(
           select format('%s é feriado em %s', public._agenda_dia_sem_mes(x.d), x.cidade)
             from (select p_d_ini + k.key::int - 1 as d,
                          (regexp_match(k.value, ' é feriado em (.+?)(?: \([^()]*\))?$'))[1] as cidade
                     from jsonb_each_text(coalesce(p_txt, '{}'::jsonb)) k) x
            where x.cidade is not null and x.d > p_de and x.d < p_ate
            order by x.d), ', '), '');
$function$;

-- (O5) "eu te aviso": a pessoa que recebeu a ficha com a frase do acesso fica sabendo quando ele vira combinado. Pelo mesmo caminho da ficha (_agenda_equipe_registrar → _agenda_equipe_enfileirar →
-- a fila), sem caminho novo e sem tabela nova: o tipo é resposta (ela responde ao que a ficha prometeu), então não pede OK da pessoa, não vira "sem resposta" e não entra na régua da ficha. A chave
-- acesso:<dia> faz uma vez só por pessoa e dia. A janela é a da ficha (a equipe, não a da resposta direta): fora dela, espera o tique seguinte. Só com modo_local_autorizacao ligado (quem chama)
-- e a ficha ligada. A OS é lida com o dia em que a ficha saiu: de lá para cá o plano começou, e _agenda_combinar_da_os não diria mais nada no próprio dia.
create or replace function public._agenda_local_avisar_acesso(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_frase constant text := ' ainda não está confirmado: eu te aviso.';
  r       record;
  v_itens jsonb;
  v_falta boolean;
  v_nomes text[];
  v_txt   text;
  v_res   jsonb;
  n_env   int := 0;
begin
  if cf.modo_equipe <> 'ligado' then
    return jsonb_build_object('pulado', 'equipe');
  end if;
  if public._agenda_equipe_fora_da_janela('ficha', p_agora, p_agora) is not null then
    return jsonb_build_object('pulado', 'janela');
  end if;
  for r in
    select distinct on (m.payee_id, x.dia) m.payee_id, x.dia, (m.enviar_em at time zone 'America/Sao_Paulo')::date as saiu_em,
           split_part(m.texto, ' O acesso ', 2) as frase
      from public.agenda_equipe_mensagens m
     cross join lateral (select case when m.tipo = 'ficha' then m.dia else m.leva_ficha_de end as dia) x
     where m.modo = 'ligado' and m.tipo in ('ficha', 'como_foi') and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
       and x.dia >= p_hoje and position(c_frase in m.texto) > 0
       and not exists (select 1 from public.agenda_equipe_mensagens a
                        where a.dedupe_key = format('agenda-equipe:resposta:%s:acesso:%s', m.payee_id, x.dia))
     order by m.payee_id, x.dia, m.enviar_em desc
  loop
    -- As OS do dia dela, como a ficha as leu. Falta alguma: espera (uma mensagem só por dia, e ela tem de ser verdade para todas)
    select coalesce(jsonb_agg(i), '[]'::jsonb) into v_itens
      from (select distinct a.service_order_id as os
              from public.agenda_alocacoes a
             where a.payee_id = r.payee_id and a.dia = r.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') o
     cross join lateral jsonb_array_elements(public._agenda_combinar_da_os(o.os, r.saiu_em)) i
     where i ->> 'tipo' = 'acesso' and (i ->> 'para')::date = r.dia;
    continue when jsonb_array_length(v_itens) = 0;
    v_falta := exists (select 1 from jsonb_array_elements(v_itens) i where not (i ->> 'combinado')::boolean);
    continue when v_falta;
    -- Só os locais que a frase citou
    v_nomes := array(select distinct public._agenda_local_no(i ->> 'local') from jsonb_array_elements(v_itens) i
                      where nullif(i ->> 'local', '') is not null and position(public._agenda_local_no(i ->> 'local') in r.frase) > 0 order by 1);
    continue when cardinality(v_nomes) = 0;
    v_txt := format('O acesso %s está confirmado para %s.', public._agenda_lista(v_nomes, null), public._agenda_dia_da_equipe(r.dia, p_hoje));
    v_res := public._agenda_equipe_registrar(r.payee_id, r.dia, 'resposta', v_txt, p_agora, null, format('acesso:%s', r.dia));
    if coalesce((v_res ->> 'criada')::boolean, false) then
      n_env := n_env + 1;
    end if;
  end loop;
  return jsonb_build_object('avisos', n_env);
end;
$function$;

-- ── As recriadas ───────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_local_no(p_nome text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case when public._agenda_normal(normalize(p_nome, nfc)) ~ '^patio\M' then 'no '
              -- FASE 7d: (correção O2) o lugar novo pode ser uma cidade: "em Nova Trento", nunca "na Nova Trento". A linha do tipo outro é a do dono; "em" serve a qualquer nome
              when exists (select 1 from public.agenda_locais x where x.nome = btrim(p_nome) and x.tipo = 'outro') then 'em '
              -- FASE 7d: fim
              else 'na ' end || btrim(p_nome);
$function$;
comment on function public._agenda_local_no(text) is
  'Agenda de Produção (Fase 7d, P3; R6.5): o local com a preposição — "no" só quando o nome começa pela palavra Pátio; senão "na". A ficha de hoje diz "na MP Motorhomes", e esse texto não pode mudar. Correção da 7d (O2): STABLE, porque lê o tipo: a linha do tipo outro é "em" (o lugar novo pode ser cidade).';

create or replace function public._agenda_local_resolvido(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_so     record;
  l        public.agenda_locais;
  v_fonte  text;
  v_classe text;
  v_cid    text;
  v_mun    text;
  v_uf     text;
  v_sup    boolean;
  v_bem    text;
  v_outra  text;
  v_nota   text;
  v_onde   text;
  v_por    text;
  v_texto  text;
  v_curto  text;
begin
  select so.marina_id, vs.marina_id as marina_do_bem, pl.local_id, pl.local_fonte, cl.city, cl.state
    into v_so
    from public.service_orders so
    left join public.vessels vs on vs.id = so.vessel_id
    left join public.clients cl on cl.id = so.client_id
    left join public.os_planejamento pl on pl.service_order_id = so.id
   where so.id = p_os;
  if not found then
    return null;
  end if;

  -- 1. o que o dono ou o cliente disse
  if v_so.local_id is not null then
    select * into l from public.agenda_locais x where x.id = v_so.local_id and x.ativo;
    if found then v_fonte := v_so.local_fonte; end if;
  end if;
  -- 2. a marina da OS
  if v_fonte is null and v_so.marina_id is not null then
    select * into l from public.agenda_locais x where x.marina_id = v_so.marina_id and x.ativo;
    if found then v_fonte := 'os'; end if;
  end if;
  -- 3. a marina do bem
  if v_fonte is null and v_so.marina_do_bem is not null then
    select * into l from public.agenda_locais x where x.marina_id = v_so.marina_do_bem and x.ativo;
    if found then v_fonte := 'bem'; end if;
  end if;
  -- 4. motorhome, camper, trailer: o pátio, suposição
  if v_fonte is null then
    v_classe := public._agenda_classe_de_campo(p_os) ->> 'bem';
    if v_classe = 'rv' then
      select * into l from public.agenda_locais x where x.tipo = 'patio_hbr' and x.ativo;
      if found then v_fonte := 'patio'; end if;
    end if;
  end if;
  -- 5. a cidade do cliente, suposição, sem local; a cidade com o caractere quebrado não serve
  if v_fonte is null then
    v_cid := nullif(btrim(coalesce(v_so.city, '')), '');
    if v_cid is not null and position(chr(65533) in v_cid) = 0 then
      v_mun := public._agenda_normal(normalize(v_cid, nfc));
      if v_mun <> '' then
        v_fonte := 'cidade';
        v_uf := nullif(upper(btrim(coalesce(v_so.state, ''))), '');
        v_uf := case when v_uf ~ '^[A-Z]{2}$' then v_uf end;
      end if;
    end if;
  end if;
  -- 6. nada
  v_fonte := coalesce(v_fonte, 'nenhum');

  -- A OS diz uma marina que não virou local: a ficha de hoje diz o nome dela, e o texto_equipe não pode dizer outro lugar.
  v_sup := v_fonte in ('patio', 'cidade');
  if v_so.marina_id is not null and v_fonte in ('bem', 'patio', 'cidade', 'nenhum') then
    select nullif(btrim(m.name), '') into v_outra from public.marinas m where m.id = v_so.marina_id;
    v_sup := v_sup or v_fonte = 'bem';
  end if;

  -- O barco cadastrado noutro lugar (NOVO-agenda-63), ou a marina da OS fora do cadastro de locais. A palavra do bem só quando vai ser lida.
  if v_fonte = 'bem' or (v_outra is null and v_so.marina_do_bem is distinct from l.marina_id and v_so.marina_do_bem is not null) then
    v_classe := coalesce(v_classe, public._agenda_classe_de_campo(p_os) ->> 'bem');
    v_bem := case v_classe when 'rv' then 'motorhome' when 'barco' then 'barco' else 'bem' end;
  end if;
  if v_outra is not null then
    v_nota := format('a OS diz %s, que não está no cadastro de locais', v_outra);
  elsif v_so.marina_do_bem is not null and v_so.marina_do_bem is distinct from l.marina_id then
    select format('o %s está cadastrado %s', v_bem, public._agenda_local_no(m.name)) into v_nota
      from public.marinas m where m.id = v_so.marina_do_bem;
  end if;

  if v_fonte = 'cidade' then
    v_curto := 'em ' || v_cid;
    v_texto := v_curto || ' (suposição: pela cidade do cliente)';
  elsif v_fonte = 'nenhum' then
    v_texto := 'não sei onde é o serviço';
  else
    v_curto := public._agenda_local_no(l.nome);
    if v_fonte = 'patio' then
      v_texto := l.nome || ' (suposição: motorhome vem ao pátio)';
    -- FASE 7d: (correção O3) a casa do cliente é um local de verdade, dito pelo dono: diz o que ele disse, com a cidade
    elsif l.tipo = 'casa_cliente' then
      v_curto := 'na casa do cliente' || coalesce(', em ' || l.municipio, '');
      v_texto := v_curto || ' (você disse)';
    -- FASE 7d: fim
    else
      -- "Marina Itajaí (pela OS)": o município só quando o nome não o diz.
      -- (correção O2) o lugar novo pode não ter cidade: o coalesce segura o nome
      v_onde := l.nome || coalesce(case when strpos(' ' || public._agenda_normal(normalize(l.nome, nfc)) || ' ',
                                                    ' ' || public._agenda_normal(normalize(l.municipio, nfc)) || ' ') > 0
                                        then '' else ', em ' || l.municipio end, '');
      v_por := case v_fonte when 'dono' then 'você disse' when 'cliente' then 'o cliente disse' when 'os' then 'pela OS'
                            else 'pelo cadastro do ' || v_bem end;
      if v_sup then
        v_texto := format('%s (suposição: %s)', v_onde, v_por);
      elsif l.uf is not null and l.uf <> all ((public._agenda_cfg()).viagem_uf_bate_volta) then
        v_texto := format('%s (%s)', v_onde, l.uf);   -- "Iate Clube Caiobá, em Guaratuba (PR)": o estado no lugar da fonte (§6.2)
      else
        v_texto := format('%s (%s)', v_onde, v_por);
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'local_id', l.id, 'nome', l.nome, 'tipo', l.tipo,
    'municipio', coalesce(l.municipio, v_cid), 'uf', coalesce(l.uf, v_uf),
    'fonte', v_fonte, 'suposicao', v_sup,
    'chave', case when l.id is not null then 'l:' || l.id::text when v_fonte = 'cidade' then 'c:' || v_mun end,
    'conferido', public._agenda_local_conferido(l.id, p_hoje),
    'nota_bem', v_nota, 'texto', v_texto, 'texto_curto', v_curto,
    'texto_equipe', case when v_fonte in ('dono', 'cliente', 'os', 'bem') and not v_sup then v_curto end);
end;
$function$;

create or replace function public._agenda_local_mascara(p_os uuid, p_d_ini date, p_d_fim date, p_hoje date, p_local jsonb default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_l      jsonb := coalesce(p_local, public._agenda_local_resolvido(p_os, p_hoje));
  l        public.agenda_locais;
  v_conf   boolean := coalesce((v_l ->> 'conferido')::boolean, false);
  v_mun    text := v_l ->> 'municipio';
  v_sab_7b boolean := c.sabado_manha <> 'nunca'
                      and (c.modo_sabado <> 'desligado' or coalesce(current_setting('agenda.sabado', true), '') = 'on');
  v_tol    interval := make_interval(mins => c.horario_tolerancia_min);
  v_ent_d  date;
  v_sai_d  date;
  v_dias   int[] := '{}';
  v_meios  int[] := '{}';
  v_mot    jsonb := '{}';
  v_notas  text[] := '{}';
  v_regras text[];
  v_fer    text;
  v_d      date;
  v_i      int;
  v_dow    int;
begin
  if v_l is null then
    return null;
  end if;
  if v_l ->> 'local_id' is not null then
    select * into l from public.agenda_locais x where x.id = (v_l ->> 'local_id')::uuid;
  end if;
  -- FASE 7d: (correção O14) o pátio suposto de quem tem viagem dita: se o dono disse que é viagem, o bem não está no pátio. Lugar desconhecido para o calendário: nem feriado do
  -- município do pátio, nem regra do local
  if v_l ->> 'fonte' = 'patio'
     and exists (select 1 from public.os_planejamento pl where pl.service_order_id = p_os and pl.viagem in ('bate_volta', 'pernoite')) then
    l := null;
    v_conf := false;
    v_mun := null;
  end if;
  -- FASE 7d: fim

  for v_i in 1 .. coalesce(p_d_fim - p_d_ini + 1, 0) loop
    v_d := p_d_ini + v_i - 1;
    v_dow := extract(isodow from v_d)::int;
    -- O feriado do município: fato público, vale sem conferir. Só o local conferido pode dizer que abre.
    v_fer := public.agenda_feriado_municipal(v_d, v_mun);
    if v_fer is not null and not (v_conf and l.feriado = 'abre') then
      v_dias := v_dias || v_i;
      v_mot := v_mot || jsonb_build_object(v_i::text,
        format('%s é feriado em %s (%s)', public._dia_curto(v_d), v_mun, regexp_replace(v_fer, '^aniversário de .*$', 'aniversário da cidade')));
      continue;
    end if;
    continue when not v_conf;
    if v_dow = 6 then
      -- O sábado do local só fecha o que a HBR abriu.
      if public.agenda_dia_util(v_d) or (v_sab_7b and public.agenda_feriado(v_d) is null) then
        if l.sabado = 'nao' then
          v_dias := v_dias || v_i;
          v_mot := v_mot || jsonb_build_object(v_i::text, format('%s: %s não abre no sábado', public._dia_curto(v_d), l.nome));
        elsif l.sabado = 'manha' then
          v_meios := v_meios || (2 * (v_i - 1) + 2);
        end if;
      end if;
    elsif v_dow < 6 and l.abre is not null then
      -- O horário de manutenção é de segunda a sexta (agenda_locais.abre).
      if l.abre > c.manha_inicio + v_tol or l.fecha < c.manha_fim - v_tol then
        v_meios := v_meios || (2 * (v_i - 1) + 1);
      end if;
      if l.abre > c.tarde_inicio + v_tol or l.fecha < c.tarde_fim - v_tol then
        v_meios := v_meios || (2 * (v_i - 1) + 2);
      end if;
    end if;
  end loop;

  -- A entrada e a retirada: índice preso em 1 (0 = não há data); depois do fim da janela o índice passa dela de propósito: o EST e os dias
  -- desde a retirada ficam certos. A retirada não entra em dias: o P4 só a aplica com modo_patio ligado.
  select pl.entrada_em, pl.retirada_em into v_ent_d, v_sai_d from public.os_planejamento pl where pl.service_order_id = p_os;

  -- As regras do cadastro que ainda não são regra: nota "a confirmar", no máximo 3.
  if l.id is not null and not v_conf then
    v_regras := array_remove(array[
      case when l.exige_autorizacao then 'pede ' || coalesce(nullif(btrim(l.autorizacao_texto), ''), 'autorização com o nome de quem vai') end,
      case when l.abre is not null then format('abre das %s às %s', to_char(l.abre, 'HH24:MI'), to_char(l.fecha, 'HH24:MI')) end,
      case l.sabado when 'nao' then 'não abre no sábado' when 'manha' then 'no sábado, só de manhã' when 'dia' then 'abre no sábado' end,
      case when l.seguro_exigido then 'pede ' || coalesce(nullif(btrim(l.seguro_texto), ''), 'seguro') end,
      nullif(btrim(coalesce(l.taxa_texto, '')), ''),
      case when l.tomada_max_w is not null then format('tomada até %s W', l.tomada_max_w) end,
      case when l.tem_garagem_seca then 'tem garagem seca' end], null);
    v_notas := array(select format('%s: %s (a confirmar com você).', l.nome, u.r)
                       from unnest(v_regras[1:3]) with ordinality u(r, o) order by u.o);
    if l.tipo = 'estaleiro' and cardinality(v_notas) < 3 then
      v_notas := v_notas || 'No estaleiro, combine com eles quando o barco fica livre para a elétrica.'::text;
    end if;
  end if;

  return jsonb_build_object('dias', to_jsonb(v_dias), 'meios', to_jsonb(v_meios), 'motivos', v_mot, 'notas', to_jsonb(v_notas),
    'ent', case when v_ent_d is null then 0 else greatest(v_ent_d - p_d_ini + 1, 1) end,   -- greatest ignora nulo: sem o case, 1 sem data
    'sai', case when v_sai_d is null then 0 else greatest(v_sai_d - p_d_ini + 1, 1) end);
end;
$function$;

create or replace function public.agenda_propor(
  p_escopo     text,
  p_de         date        default null,
  p_ate        date        default null,
  p_os         uuid[]      default null,
  p_restricoes jsonb       default '{}'::jsonb,
  p_persistir  boolean     default false,
  p_origem     text        default 'motor',
  p_autor      uuid        default null,
  p_hoje       date        default public._hoje_brt(),
  p_agora      timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  -- Os pesos da pontuação (plano §4.4, os do Timefold): estrutura para comparar alternativas, não parâmetro do dono.
  c_peso_atraso  constant int := 1000000;
  c_peso_mudanca constant int := 100;
  c_peso_dono    constant int := 10;
  c_peso_interr  constant int := 50;
  c_peso_fim     constant int := 1;
  -- "atrasar" leva a OS para o fim da classe: a ordem dela passa à frente de qualquer posição real da fila.
  c_fim_da_classe constant int := 1000000;
  -- quantas OS que X empurraria entram na pergunta "não cabe" (as mais próximas dela na fila)
  c_candidatas   constant int := 3;
  cf        public.agenda_config;
  v_r       jsonb := coalesce(p_restricoes, '{}'::jsonb);
  v_modo    text;
  v0        bigint;
  v_cong    date;
  v_seg     date;
  v_de      date;
  v_ate     date;
  v_hor     date;
  v_ini     date;
  v_fim     date;
  v_cart    uuid[];
  v_cartj   jsonb;
  v_escopo  uuid[];
  v_tirar   uuid[];
  v_atrasar uuid[];
  v_aceitar uuid[];
  v_acima   boolean;
  v_decisao uuid;
  v_fixar   jsonb;
  v_depois  jsonb;
  v_info    jsonb := '{}'::jsonb;
  v_canc    jsonb;
  v_ign     uuid[];
  v_fila_os uuid[];
  v_ctx     jsonb;
  v_pes     uuid[];
  v_fila    jsonb := '[]'::jsonb;
  v_ent     jsonb;
  v_par     jsonb;
  v_parh    jsonb;
  v_r0      jsonb;
  v_rf      jsonb;
  v_ctxf    jsonb;
  v_base    jsonb;
  v_sim     jsonb;
  v_minh_n  int;
  v_minh_a  int;
  v_os      uuid;
  v_i       int;
  v_e       jsonb;
  v_b       jsonb;
  v_pront   jsonb;
  v_meios   jsonb;
  v_pl      record;
  v_status  text;
  v_k       record;
  v_cl      jsonb;
  v_classe  int;
  v_fx      jsonb;
  v_fp      int;
  v_evento  boolean;
  v_passos  int;
  v_abre    boolean;
  v_fecha   boolean;
  v_dtm     boolean;
  v_dtt     boolean;
  v_fixa    int;
  v_pm      int[];
  v_pt      int[];
  v_est     date;
  v_estc    date;
  v_minh    int;
  v_bem     int[];
  v_pat_p   int;
  v_pat_b   int[];
  v_bem_tudo boolean;
  v_fora    jsonb := '[]'::jsonb;
  v_crit    jsonb := '{}'::jsonb;
  v_xnc     int[] := '{}';
  v_xoc     int[] := '{}';
  v_cands   jsonb := '{}'::jsonb;
  v_h       int[] := '{}';
  v_sem_q   int[] := '{}';
  v_tentativa int;
  v_usadas  jsonb;
  v_perg    jsonb := '[]'::jsonb;
  v_held    jsonb := '[]'::jsonb;
  v_itens   jsonb := '[]'::jsonb;
  v_opc     jsonb;
  v_rec     int;
  v_rec_txt text;
  v_txt     text;
  v_chave   text;
  v_tipo    text;
  v_fim_x   date;
  v_ini_x   date;
  v_fim_c   date;
  v_ini_c   date;
  v_x       int;
  v_c       int;
  v_cb      jsonb;
  v_xb      jsonb;
  v_canc_os uuid[];
  v_ini_antes date;
  v_fim_dep date;
  v_carga   jsonb;
  v_textos  jsonb;
  v_linhas  text[];
  v_tfora   text[];
  v_titulo  text;
  v_texto   text;
  v_pont    jsonb;
  v_viol    jsonb;
  v_pid     uuid;
  v_expira  timestamptz;
  v_dono    uuid := public._agenda_dono(null);
  v_feriados text[];
  v_q       jsonb;
  v_n       int;
  v_aviso   text;
  -- CORREÇÃO 29/10 (P3): a reserva da própria OS no encaixe do compromisso dela (res_propria) e o resumo que separa o
  -- marcado firme do reservado
  v_rp       int[];
  v_marc     text[];
  v_resv     text[];
  v_contagem text;
  -- CORREÇÃO 29/10 (P3): fim
  -- FASE 7: (7a P8) a zona travada: o que fica fora da conta do dia já avisado
  v_f7_fora uuid[];
  -- FASE 7: fim
  -- FASE 7b: (7b P4) a dupla por meio-dia, o prazo firme, o sábado e as linhas em teste
  v_7b_pk     int[];
  v_7b_dk     int[];
  v_7b_tot    int;
  v_7b_prazo  date;
  v_7b_n      int;
  v_7b_semtec int;
  v_7b_tec    text[];
  v_7b_teste  text[] := '{}';
  v_7b_b      jsonb;
  v_7b_e      jsonb;
  v_7b_x      text;
  v_7b_y      text;
  v_7b_dias   date[];
  v_7b_nomes  text[];
  v_7b_z      text;
  v_7b_n2     int;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 22 e 23) o exemplo com todos os dias e a dupla dita antes de a OS ficar pronta
  v_7bc_dias date[];
  v_7bc_est  date;
  v_7bc_max  date;
  -- FASE 7b: fim
  -- FASE 7c: (7c P2) o que a OS pede, o responsável, os motivos e os textos da 7c
  v_7c_exg   jsonb;
  v_7c_ld    jsonb;
  v_7c_lp    int;
  v_7c_mot   text[];
  v_7c_txt   text;
  v_7c_d     int;
  v_7c_le    boolean;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção, achado 9) a troca avisada do responsável no texto do item
  c_c9_max   constant int := 320;   -- estrutural: o item com a frase a mais (o texto da ação junta os itens da OS em até 400)
  v_c9_tr    text;
  v_c9_txt   text;
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4, R6.7b, R6.8-1) os modos da 7d (por _agenda_local_modo: ligado com *gestor, só propor* = em teste) e, por OS da fila, o local
  -- (v_7d_lr), a máscara (v_7d_lm), a viagem (v_7d_vi), o bem (v_7d_bm), a suposição do abre e fecha (v_7d_saf) e as suposições do item
  v_7d_cal   boolean;
  v_7d_pat   boolean;
  v_7d_via   boolean;
  v_7d_ml    boolean;
  v_7d_bem   boolean;
  v_7d_lr    jsonb;
  v_7d_lm    jsonb;
  v_7d_vi    jsonb;
  v_7d_bm    jsonb;
  v_7d_saf   boolean;
  v_7d_sup   text[];
  v_7d_extra int;
  v_7d_x     int;
  v_7d_os    uuid;
  -- FASE 7d: fim
  -- FASE 7d: (correção O15) o feriado do município no texto do item
  v_7d_dt  text;
  v_7d_mf  text;
  -- FASE 7d: fim
begin
  -- ── 0. Entrada ──
  if p_escopo is null or p_escopo not in ('semana', 'os', 'replano') then
    raise exception 'Escopo desconhecido: "%" (semana, os ou replano).', coalesce(p_escopo, '') using errcode = '22023';
  end if;
  if p_origem is null or p_origem not in ('motor', 'vigia', 'dono', 'assistente', 'tela', 'aprovacao') then
    raise exception 'Origem desconhecida: "%".', coalesce(p_origem, '') using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null or jsonb_typeof(v_r) <> 'object' then
    raise exception 'Faltam o dia, a hora ou as restrições do plano.' using errcode = '22023';
  end if;
  if p_escopo in ('os', 'replano') and coalesce(cardinality(p_os), 0) = 0 then
    raise exception 'Diga de que OS é o plano.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  if p_persistir then
    perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  end if;
  cf := public._agenda_cfg();
  v_modo := cf.modo_proposta;
  if p_persistir and v_modo = 'desligado' then
    return jsonb_build_object('ok', false, 'simulacao', false, 'texto', 'A agenda automática está desligada: não monto o plano.');
  end if;
  -- FASE 7d: (7d P4, R6.7b) todo leitor de modo usa _agenda_local_modo, nunca cf.modo_x
  v_7d_cal := public._agenda_local_modo('calendario') = 'ligado';
  v_7d_pat := public._agenda_local_modo('patio') = 'ligado';
  v_7d_via := public._agenda_local_modo('viagem') = 'ligado';
  v_7d_ml := public._agenda_local_modo('mesmo_local') = 'ligado';
  v_7d_bem := public._agenda_local_modo('bem') = 'ligado';
  -- FASE 7d: fim
  v0 := cf.versao_plano;
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);

  -- ── 1. A janela ──
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1);
  if p_escopo = 'semana' then
    v_de := coalesce(p_de, public.agenda_somar_du(v_seg + 7, 0));
    v_ate := coalesce(p_ate, v_seg + 7 + 5);
  else
    v_de := coalesce(p_de, public.agenda_somar_du(v_cong, 1));
    v_ate := coalesce(p_ate, v_de + 7 * cf.horizonte_semanas);
  end if;
  if v_ate < v_de then
    raise exception 'O período do plano termina antes de começar (% a %).', v_de, v_ate using errcode = '22023';
  end if;
  v_hor := greatest(p_hoje + 7 * cf.horizonte_semanas, v_ate);
  v_ini := v_seg;
  v_fim := v_hor + (7 - extract(isodow from v_hor)::int);

  -- ── Restrições (ids e datas já resolvidos por quem chama) ──
  v_tirar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'tirar', '[]'::jsonb)) x);
  v_atrasar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'atrasar', '[]'::jsonb)) x);
  v_aceitar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'aceitar_atraso', '[]'::jsonb)) x);
  v_acima := coalesce((v_r ->> 'acima_da_carga')::boolean, false);
  v_decisao := nullif(v_r ->> 'decisao', '')::uuid;
  if exists (select 1 from jsonb_array_elements(coalesce(v_r -> 'fixar', '[]'::jsonb)) e
              where e ->> 'os' is null or e ->> 'de' is null) then
    raise exception 'fixar precisa da OS e do dia.' using errcode = '22023';
  end if;
  select coalesce(jsonb_object_agg(e ->> 'os', jsonb_build_object('de', e -> 'de', 'ate', coalesce(e -> 'ate', e -> 'de'),
                                                                  'pessoa', e -> 'pessoa')), '{}'::jsonb)
    into v_fixar from jsonb_array_elements(coalesce(v_r -> 'fixar', '[]'::jsonb)) e;
  select coalesce(jsonb_object_agg(e ->> 'os', e -> 'dia'), '{}'::jsonb)
    into v_depois from jsonb_array_elements(coalesce(v_r -> 'so_depois_de', '[]'::jsonb)) e;

  -- ── 2. A carteira, o escopo e o que se sabe de cada OS ──
  select coalesce(array_agg(k.service_order_id order by k.numero collate "C", k.service_order_id), '{}'::uuid[]),
         coalesce(jsonb_object_agg(k.service_order_id::text, jsonb_build_object('sinal', k.sinal_pago > 0, 'aprovada_em', k.aprovada_em)), '{}'::jsonb)
    into v_cart, v_cartj
    from public.os_carteira(p_hoje) k;
  if p_escopo = 'semana' then
    v_escopo := v_cart;
  else
    v_escopo := array(select distinct x from unnest(p_os) x order by 1);
  end if;
  for v_os in
    select x from (select unnest(v_escopo) as x
                   union
                   select a.service_order_id from public.agenda_alocacoes a
                    where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                      and p_escopo = 'semana' and not (a.service_order_id = any (v_cart))) q
     order by 1
  loop
    v_info := v_info || jsonb_build_object(v_os::text, jsonb_build_object(
                'pront', public.os_prontidao(v_os, p_hoje), 'meios', public.agenda_meios_da_os(v_os, p_hoje)));
  end loop;

  -- ── 3. Estabilidade: o que não pode mais acontecer sai (e o pedido do dono tira o que a OS tinha) ──
  v_canc := public._agenda_violacoes(v_escopo, v_cart, p_escopo = 'semana', v_info, p_hoje, v_cong);
  v_canc := v_canc || coalesce((
    select jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'os', a.service_order_id, 'motivo', 'dono', 'violada', false,
             'congelado', a.dia <= v_cong, 'tipo', a.tipo, 'estado', a.estado, 'fixado_por', a.fixado_por,
             'reserva_de', a.reserva_de, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca)
             order by a.service_order_id, a.dia, a.turno = 'tarde', a.payee_id, a.id)
      from public.agenda_alocacoes a
     where v_fixar ? a.service_order_id::text and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje
       and a.resultado is null and lower(a.periodo) > p_agora
       and not exists (select 1 from jsonb_array_elements(v_canc) c where (c ->> 'alocacao_id')::uuid = a.id)), '[]'::jsonb);
  v_ign := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c);

  -- ── 4. A grade e a fila ──
  v_fila_os := array(select x from unnest(v_escopo) x where not (x = any (v_tirar)) order by 1);
  v_ctx := public._agenda_contexto(v_ini, v_fim, p_hoje, v_ign, v_fila_os);
  v_pes := array(select x::uuid from jsonb_array_elements_text(v_ctx -> 'pessoas') x);
  -- o 1º meio-dia que dá: depois do congelado; e, para o evento real e o pedido do dono, o 1º que ainda não começou
  v_minh_n := 2 * (v_cong + 1 - v_ini) + 1;
  v_minh_a := case when lower(public.agenda_periodo(p_hoje, 'manha')) > p_agora then 2 * (p_hoje - v_ini) + 1
                   when lower(public.agenda_periodo(p_hoje, 'tarde')) > p_agora then 2 * (p_hoje - v_ini) + 2
                   else 2 * (p_hoje + 1 - v_ini) + 1 end;

  for v_os in select unnest(v_tirar) loop
    if v_os = any (v_escopo) then
      v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'tirado', 'texto', public._agenda_rotulo_da_os(v_os) || ': você tirou.');
    end if;
  end loop;

  for v_i in 1 .. coalesce(cardinality(v_fila_os), 0) loop
    v_os := v_fila_os[v_i];
    v_pront := v_info -> v_os::text -> 'pront';
    v_meios := v_info -> v_os::text -> 'meios';
    select pl.* into v_pl from public.os_planejamento pl where pl.service_order_id = v_os;
    select so.status into v_status from public.service_orders so where so.id = v_os;
    -- o que fica do plano dela (sem o que a proposta cancela)
    select count(distinct (a.dia, a.turno)) filter (where a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null) as fut,
           coalesce(bool_or(a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido'), false) as algum,
           max(a.dia) filter (where a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido') as ultimo,
           max(a.dia) filter (where a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null) as ultimo_fut,
           coalesce(bool_or(a.tipo <> 'reserva' and a.estado = 'fixada' and a.dia >= p_hoje and a.resultado is null), false) as fixada,
           coalesce(bool_or(a.tipo = 'reserva' and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje), false) as reserva,
           coalesce(bool_or(a.tipo = 'reserva' and a.reserva_de = 'patio' and a.dia >= p_hoje), false) as patio
      into v_k
      from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and not (a.id = any (v_ign));
    v_bem_tudo := (v_pl.bem_indisponivel is not null and not isempty(v_pl.bem_indisponivel)
                   and not exists (select 1 from generate_series(p_hoje + 1, v_hor, interval '1 day') g
                                    where not (v_pl.bem_indisponivel @> g::date)))
                  or coalesce(v_pl.nao_antes_de > v_hor, false);
    v_cl := public._agenda_classe_da_os(v_pront, v_meios, p_hoje, v_k.fixada, v_bem_tudo);
    v_classe := (v_cl ->> 'classe')::int;
    v_fx := v_fixar -> v_os::text;
    if v_fx is not null then
      if v_classe = 4 then
        v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'fixar_recusado',
                   'texto', format('%s: %s.', public._agenda_rotulo_da_os(v_os), rtrim(v_cl ->> 'texto', '.')));
        continue;
      end if;
      v_classe := 1;
    end if;
    v_evento := exists (select 1 from jsonb_array_elements(v_canc) c
                         where (c ->> 'os')::uuid = v_os and (c ->> 'violada')::boolean
                           and ((c ->> 'congelado')::boolean or (v_cl ->> 'classe')::int = 1));
    v_passos := case when (v_meios ->> 'total') is null then 0
                     else ceil(greatest((v_meios ->> 'total')::numeric - coalesce((v_meios ->> 'cumpridos')::numeric, 0)
                                        - coalesce(v_k.fut, 0), 0))::int end;
    v_fecha := v_meios ->> 'presenca' = 'abre_e_fecha';
    v_abre := v_fecha and not v_k.algum and coalesce((v_meios ->> 'cumpridos')::numeric, 0) = 0 and v_status <> 'in_progress';
    v_dtm := coalesce((v_meios #>> '{dono_turno,manha}')::boolean, false);
    v_dtt := coalesce((v_meios #>> '{dono_turno,tarde}')::boolean, false);
    v_fixa := 0;
    if v_fx is not null and v_fx ->> 'pessoa' is not null then
      v_fp := array_position(v_pes, (v_fx ->> 'pessoa')::uuid);
      if v_fp is null then
        v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'fixar_recusado',
                   'texto', format('%s: essa pessoa não está na equipe de agora.', public._agenda_rotulo_da_os(v_os)));
        continue;
      elsif v_fp = (v_ctx ->> 'dono')::int then
        v_dtm := true; v_dtt := true; v_abre := false; v_fecha := false;
      else
        v_fixa := v_fp;
      end if;
    end if;
    v_pm := array(select array_position(v_pes, (e ->> 'payee_id')::uuid)
                    from jsonb_array_elements(coalesce(v_meios #> '{por_turno,manha,pessoas}', '[]'::jsonb)) with ordinality t(e, o)
                   where array_position(v_pes, (e ->> 'payee_id')::uuid) is not null order by o);
    v_pt := array(select array_position(v_pes, (e ->> 'payee_id')::uuid)
                    from jsonb_array_elements(coalesce(v_meios #> '{por_turno,tarde,pessoas}', '[]'::jsonb)) with ordinality t(e, o)
                   where array_position(v_pes, (e ->> 'payee_id')::uuid) is not null order by o);
    -- EST': o dia em que fica pronta, depois do congelado (o evento real e o pedido do dono podem usar o que ainda não
    -- começou), depois do "só depois de" e depois do que ela já tem marcado.
    if v_fx is not null then
      v_est := greatest((v_fx ->> 'de')::date, p_hoje);
      v_minh := v_minh_a;
    elsif v_evento then
      v_est := greatest(coalesce((v_pront #>> '{material,inicio_mat}')::date, p_hoje), v_pl.nao_antes_de, p_hoje,
                        (v_depois ->> v_os::text)::date, v_k.ultimo_fut);
      v_minh := v_minh_a;
    else
      v_est := greatest(coalesce((v_pront ->> 'est')::date, (v_pront ->> 'est_sem_material')::date, p_hoje),
                        public.agenda_somar_du(v_cong, 1), (v_depois ->> v_os::text)::date, v_k.ultimo_fut);
      v_minh := v_minh_n;
    end if;
    v_estc := greatest(coalesce((v_pront ->> 'est')::date, (v_pront ->> 'est_sem_material')::date, p_hoje),
                       public.agenda_somar_du(v_cong, 1), (v_depois ->> v_os::text)::date);
    v_bem := array(select g + 1 from generate_series(0, v_fim - v_ini) g
                    where coalesce(v_pl.bem_indisponivel @> (v_ini + g), false));
    -- o pátio: o que dá para adiantar sem o bem, enquanto ele está fora (dentro da janela)
    v_pat_p := 0;
    v_pat_b := '{}';
    if v_pl.adiantavel_patio_dias is not null and not v_k.patio and v_classe in (1, 2, 3) and v_passos > 0
       and exists (select 1 from generate_series(greatest(v_de, public.agenda_somar_du(v_cong, 1)), v_ate, interval '1 day') g
                    where coalesce(v_pl.bem_indisponivel @> g::date, false)) then
      v_pat_p := (v_pl.adiantavel_patio_dias * 2)::int;
      v_pat_b := array(select g + 1 from generate_series(0, v_fim - v_ini) g
                        where not coalesce(v_pl.bem_indisponivel @> (v_ini + g), false));
    end if;
    -- FASE 7d: (7d P4, §5.4 1, R6.8-1) o local no motor, só com calendario, patio, viagem ou mesmo_local ligado: em teste, nenhuma chamada. O dia que
    -- o local não recebe entra em v_bem; a entrada do bem, no EST; os dias desde a retirada, em v_bem. A viagem fora da região não tem abre e
    -- fecha; o custo dela em meios-dias entra no item da fila, lá embaixo, depois da dupla da 7b, que lê v_passos. Com modo_bem ligado, o
    -- estado do bem, para a suposição gravada.
    v_7d_lr := null;
    v_7d_lm := null;
    v_7d_vi := null;
    v_7d_bm := null;
    v_7d_saf := false;
    if v_7d_cal or v_7d_pat or v_7d_via or v_7d_ml then
      v_7d_lr := public._agenda_local_resolvido(v_os, p_hoje);
      if v_7d_cal or v_7d_pat then
        v_7d_lm := public._agenda_local_mascara(v_os, v_ini, v_fim, p_hoje, v_7d_lr);
      end if;
      if v_7d_cal then
        v_bem := v_bem || public._agenda_ints(v_7d_lm -> 'dias');
      end if;
      if v_7d_pat and (v_7d_lm ->> 'ent')::int > 0 then
        v_est := greatest(v_est, v_ini + (v_7d_lm ->> 'ent')::int - 1);
        v_estc := greatest(v_estc, v_ini + (v_7d_lm ->> 'ent')::int - 1);
      end if;
      if v_7d_pat and (v_7d_lm ->> 'sai')::int > 0 then
        v_bem := v_bem || array(select g from generate_series((v_7d_lm ->> 'sai')::int, v_fim - v_ini + 1) g);
      end if;
      if v_7d_via then
        v_7d_vi := public._agenda_viagem_da_os(v_os, p_hoje, v_7d_lr);
        if coalesce((v_7d_vi ->> 'sem_abre_fecha')::boolean, false) then
          v_7d_saf := v_abre or v_fecha;
          v_abre := false;
          v_fecha := false;
        end if;
      end if;
    end if;
    if v_7d_bem then
      v_7d_bm := public._agenda_estado_do_bem(v_os, p_hoje);
    end if;
    -- FASE 7d: fim
    v_e := jsonb_build_object(
      'i', v_i, 'os', v_os, 'numero', v_pront ->> 'numero', 'cliente_curto', v_pront ->> 'cliente_curto',
      'classe', v_classe, 'motivo', v_cl ->> 'motivo', 'texto', v_cl ->> 'texto', 'condicao_tipo', v_cl ->> 'condicao_tipo',
      'passos', v_passos, 'abre', v_abre, 'fecha', v_fecha, 'dt_m', v_dtm, 'dt_t', v_dtt,
      'dm', coalesce((v_meios #>> '{por_turno,manha,desejado}')::int, 0), 'dtd', coalesce((v_meios #>> '{por_turno,tarde,desejado}')::int, 0),
      'pm', to_jsonb(v_pm), 'pt', to_jsonb(v_pt), 'fixa', v_fixa,
      'est', v_est - v_ini + 1, 'est_cond', v_estc - v_ini + 1, 'est_patio', public.agenda_somar_du(v_cong, 1) - v_ini + 1,
      'min_h', v_minh, 'bem', to_jsonb(v_bem), 'patio_passos', v_pat_p, 'patio_bem', to_jsonb(v_pat_b),
      'tem_reserva', v_k.reserva, 'tem_fixada', v_k.fixada, 'evento_real', v_evento, 'teto100', v_fx is not null,
      'dono_impossivel', ((v_dtm or v_dtt) and not coalesce((v_ctx ->> 'dono_tem_padrao')::boolean, false))
                         or ((v_abre or v_fecha or v_dtm or v_dtt) and coalesce((v_ctx ->> 'dono')::int, 0) = 0),
      'atrasar', v_os = any (v_atrasar), 'prio', v_pl.prioridade_manual, 'razao', v_pront -> 'razao_critica',
      'sinal', coalesce((v_cartj -> v_os::text ->> 'sinal')::boolean, false), 'aprovada_em', v_pront ->> 'aprovada_em',
      'fonte', v_meios ->> 'fonte', 'dias', v_meios -> 'dias', 'precisa', v_pl.precisa_ate,
      'fim_antes', v_pront #>> '{plano,ultimo_dia}', 'kept_max', v_k.ultimo, 'tipo_os',
      -- o tipo do meio-dia: o motivo da regra d05 (diagnóstico, comissionamento), mesmo quando o dono está na equipe
      case v_meios ->> 'regra_motivo' when 'diagnóstico' then 'diagnostico' when 'comissionamento' then 'comissionamento'
           else 'execucao' end)
      || case when v_fx is not null then jsonb_build_object('fixar_de', greatest((v_fx ->> 'de')::date, p_hoje) - v_ini + 1,
                                                            'fixar_ate', (v_fx ->> 'ate')::date - v_ini + 1)
              else '{}'::jsonb end;
    -- CORREÇÃO 29/10 (P3): a reserva DELA (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira
    -- compromisso" cancela) não conta contra ela mesma no encaixe do compromisso. O encaixe já deixava o compromisso usar a
    -- célula da própria reserva, mas o lugar até 100% da semana (teto100 − compromisso − reserva) contava a reserva dela:
    -- com o teto apertado (o João, 4 de 4 meios-dias na semana, todos na reserva do Lenine) a promoção nunca cabia. Vai na
    -- entrada da fila só quando há: res_propria = a pessoa × semana ((pessoa − 1) × nw + semana, a posição de uso_r no
    -- contexto) de cada meio-dia reservado, uma vez por alocação.
    if v_k.reserva then
      v_rp := array(select (array_position(v_pes, a.payee_id) - 1) * (v_ctx ->> 'nw')::int + (a.dia - v_ini) / 7 + 1
                      from public.agenda_alocacoes a
                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva'
                       and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje and a.dia between v_ini and v_fim
                       and a.presenca = 'turno' and a.payee_id = any (v_pes) and not (a.id = any (v_ign))
                     order by 1);
      if cardinality(v_rp) > 0 then
        v_e := v_e || jsonb_build_object('res_propria', to_jsonb(v_rp));
      end if;
    end if;
    -- CORREÇÃO 29/10 (P3): fim
    -- FASE 7b: (7b P4, §5.3, R4.3) a entrada da fila, só com os modos da 7b: a dupla por meio-dia (dk = as pessoas dos passos que
    -- restam, os últimos v_passos do molde; dk_dono_conta; a fonte; o texto do cartão); da dupla inferida, o bloco de 1 pessoa
    -- (passos1: ligado com a duração que conserva as diárias-pessoa, a soma do dk — cada meio-dia de dupla vira dois de 1 pessoa —; em
    -- teste ou com os dias ditos pelo dono, os passos de antes), os meios-dias
    -- dela que restam no início e no fim (dupla_ni, dupla_nf; ou dupla_todos) e o nome do que a tarefa pede; o prazo firme (prazo_h =
    -- o índice da tarde de least(precisa_ate, o prometido firme) na grade); e a dupla dita que só passa pela régua dos técnicos com
    -- quem vem sob demanda (dupla_sd: sem eles, a classe daria 4; R4.3(c)).
    v_7b_dk := '{}'::int[];
    if v_meios ? 'dk' then
      v_7b_pk := public._agenda_ints(v_meios #> '{dupla,pk}');
      v_7b_tot := cardinality(v_7b_pk);
      v_7b_dk := case when v_passos > 0 then v_7b_pk[greatest(v_7b_tot - v_passos + 1, 1) : v_7b_tot] else '{}'::int[] end;
      v_e := v_e || jsonb_build_object('dk', to_jsonb(v_7b_dk), 'dk_dono_conta', v_meios -> 'dk_dono_conta',
                                       'dupla_fonte', v_meios #>> '{dupla,fonte}', 'dupla_texto', v_meios #>> '{dupla,texto}');
      if v_meios #>> '{dupla,fonte}' = 'regra' and v_passos > 0 then
        v_e := v_e || jsonb_build_object(
          'passos1', case when (v_meios #>> '{dupla,pm_estimativa}') is not null then (select sum(x)::int from unnest(v_7b_dk) x)
                          else v_passos end,
          'dupla_todos', coalesce((v_meios #>> '{dupla,todos}')::boolean, false),
          'dupla_ni', least(greatest(coalesce((v_meios #>> '{dupla,ni}')::int, 0) - (v_7b_tot - v_passos), 0), v_passos),
          'dupla_nf', least(coalesce((v_meios #>> '{dupla,nf}')::int, 0), v_passos),
          'dupla_rot_ini', public._agenda_lista(array(select distinct on (m ->> 'motivo') m ->> 'frase'
                                                        from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                                                       where m ->> 'onde' = 'inicio' order by m ->> 'motivo')),
          'dupla_rot_fim', public._agenda_lista(array(select distinct on (m ->> 'motivo') m ->> 'frase'
                                                        from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                                                       where m ->> 'onde' = 'fim' order by m ->> 'motivo')),
          'dupla_rot_todos', (select m ->> 'rotulo' from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                               where m ->> 'onde' = 'todos' limit 1));
      end if;
    end if;
    if cf.dono_como_tecnico and cf.modo_dias <> 'desligado' and v_meios ->> 'presenca' = 'nunca' then
      v_e := v_e || jsonb_build_object('dono_nunca', true);
    end if;
    if cf.modo_sabado <> 'desligado' or v_meios ? 'dk' then
      v_7b_prazo := least(v_pl.precisa_ate, case when v_pl.prometido_tipo = 'firme' then v_pl.prometido_ate end);
      if v_7b_prazo between v_ini and v_fim then
        v_e := v_e || jsonb_build_object('prazo_h', 2 * (v_7b_prazo - v_ini) + 2, 'prazo', v_7b_prazo);
      end if;
    end if;
    if cf.modo_dupla <> 'desligado' and v_pl.dupla_dita in ('todos', 'inicio', 'fim')
       and not coalesce((v_meios ->> 'equipe_dita')::boolean, false) and v_passos > 0 then
      v_7b_n := greatest(coalesce((v_meios #>> '{por_turno,manha,desejado}')::int, 0),
                         coalesce((v_meios #>> '{por_turno,tarde,desejado}')::int, 0),
                         coalesce((select max(x) from unnest(v_7b_dk) x), 0)
                         - case when coalesce((v_meios ->> 'dk_dono_conta')::boolean, true)
                                     and (coalesce((v_meios #>> '{dono_turno,manha}')::boolean, false)
                                          or coalesce((v_meios #>> '{dono_turno,tarde}')::boolean, false)) then 1 else 0 end);
      if v_7b_n >= 2 then
        v_7b_semtec := coalesce(v_7b_semtec, (select count(*)::int from jsonb_array_elements(coalesce(
                         public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb)) x
                        where not coalesce((x ->> 'eh_dono')::boolean, false)));
        if v_7b_semtec < v_7b_n then
          v_e := v_e || jsonb_build_object('dupla_sd', true, 'dupla_n', v_7b_n,
                                           'dupla_meios_n', case when cardinality(v_7b_dk) > 0
                                                                 then (select count(*)::int from unnest(v_7b_dk) x where x >= 2)
                                                                 else v_passos end);
        end if;
      end if;
    end if;
    -- FASE 7b: fim
    -- FASE 7c: (7c P2, §5.2 1) a entrada da fila ganha o que a OS pede (os_exigencias, sem IA: ext = em todos os meios-dias, exu = no
    -- último, exf 1 = pela linha, exig_texto) — em qualquer modo, porque o critério de cada alocação é gravado sempre — e, só com
    -- modo_lider ou modo_habilidade ligado, o responsável (_agenda_lider_da_os, sem as alocações que a proposta cancela): lid (a
    -- posição na grade; fora dela, 0), lid_duro (o dito ou quem fez, com modo_lider ligado e sem a palavra do dono sobre quem vai),
    -- lid_plan (o planejado: só desempata) e lid_fora (o responsável que não está na grade). Só a OS que vai ao encaixe (fora da
    -- classe 4, com passos ou o pátio) é lida. O que a OS pede só é lido com a porta de os_exigencias aberta (o service_role, sem
    -- login, ou o admin/financeiro logado): a técnica logada que marca pela tela (agenda_marcar_os, liberada a authenticated) chega
    -- aqui e receberia o 42501 dela no meio do motor; para ela, a OS "não pede ninguém em especial" (a escolha de antes; o pedido dela
    -- tem a pessoa, a palavra de quem marca, e os filtros 3 a 5 não valem de todo jeito).
    if v_7c_le is null then
      begin
        v_7c_le := case when auth.uid() is not null then public.is_admin_or_financial(auth.uid())
                        else coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') in ('', 'service_role') end;
      exception when others then
        v_7c_le := false;
      end;
    end if;
    if v_7c_le and v_classe <> 4 and (v_passos > 0 or v_pat_p > 0) then
      v_7c_exg := public.os_exigencias(v_os, p_hoje);
      v_e := v_e || jsonb_build_object('ext', coalesce((v_7c_exg ->> 'todos')::int, 0), 'exu', coalesce((v_7c_exg ->> 'ultimo')::int, 0),
                                       'exf', coalesce((v_7c_exg ->> 'fonte_texto')::int, 0), 'exig_texto', v_7c_exg ->> 'texto_curto');
      if cf.modo_lider = 'ligado' or cf.modo_habilidade = 'ligado' then
        v_7c_ld := public._agenda_lider_da_os(v_os, p_hoje, v_ign);
        if v_7c_ld is not null then
          v_7c_lp := array_position(v_pes, (v_7c_ld ->> 'payee_id')::uuid);
          v_e := v_e || jsonb_build_object('lid', coalesce(v_7c_lp, 0), 'lid_nome', v_7c_ld ->> 'nome',
                   'lid_duro', v_7c_ld ->> 'fonte' in ('dono', 'fez') and cf.modo_lider = 'ligado' and v_7c_lp is not null
                               and not (coalesce(cardinality(v_pm), 0) + coalesce(cardinality(v_pt), 0) > 0 or v_fixa > 0),
                   'lid_plan', case when v_7c_ld ->> 'fonte' = 'planejado' then coalesce(v_7c_lp, 0) else 0 end,
                   'lid_fora', v_7c_lp is null);
        end if;
      end if;
    end if;
    -- FASE 7c: fim
    -- FASE 7d: (7d P4, §5.4 2, §3.1-5, R6.8-3) a entrada da fila, só com os modos ligados (chave AUSENTE fora disso): fora_h e local_txt (a máscara),
    -- viagem, imax_os, os meios de estrada somados aos passos (depois da dupla da 7b, que corta o molde por v_passos: os meios de estrada
    -- não têm dk e pedem o desejado), local_texto e suposicoes (as da cadeia do local, da viagem e do bem, para o item da proposta)
    if v_7d_lr is not null or v_7d_bm is not null then
      v_7d_sup := '{}';
      if v_7d_lr ->> 'fonte' = 'cidade' or (v_7d_lr ->> 'fonte' = 'bem' and (v_7d_lr ->> 'suposicao')::boolean) then
        v_7d_sup := v_7d_sup || (v_7d_lr ->> 'texto');
      elsif v_7d_lr ->> 'fonte' = 'patio' and v_7d_bm is null then
        v_7d_sup := v_7d_sup || format('supus o motorhome %s', v_7d_lr ->> 'texto_curto');
      end if;
      if coalesce((v_7d_vi ->> 'suposicao')::boolean, false) and v_7d_vi ->> 'tipo' in ('bate_volta', 'pernoite') then
        v_7d_sup := v_7d_sup || public._agenda_viagem_suposicao(v_7d_lr, v_7d_vi ->> 'tipo');
      end if;
      if v_7d_saf then
        v_7d_sup := v_7d_sup || 'supus que você não vai abrir e fechar esse serviço (fora da região)'::text;
      end if;
      v_7d_sup := v_7d_sup || array(select x from jsonb_array_elements_text(coalesce(v_7d_bm -> 'suposicoes', '[]'::jsonb)) x)
                           || array(select x from jsonb_array_elements_text(coalesce(v_7d_lm -> 'notas', '[]'::jsonb)) x);
      v_e := v_e || jsonb_build_object('suposicoes', to_jsonb(v_7d_sup));
      if v_7d_lr is not null then
        v_e := v_e || jsonb_build_object('local_texto', v_7d_lr ->> 'texto', 'local_curto', v_7d_lr ->> 'texto_curto');
      end if;
      if v_7d_cal then
        v_e := v_e || jsonb_build_object('fora_h', v_7d_lm -> 'meios', 'local_txt', v_7d_lm -> 'motivos');
      end if;
      if v_7d_vi is not null then
        v_e := v_e || jsonb_build_object('viagem', v_7d_vi ->> 'tipo')
                   || case when v_7d_vi ->> 'imax_os' is not null then jsonb_build_object('imax_os', (v_7d_vi ->> 'imax_os')::int) else '{}'::jsonb end;
        v_7d_extra := public._agenda_viagem_extra(v_7d_vi ->> 'tipo', (v_7d_vi ->> 'extra_por')::int, v_passos);
        if v_7d_extra > 0 then
          v_e := v_e || jsonb_build_object('passos', v_passos + v_7d_extra)
                     || case when v_e ? 'passos1' then jsonb_build_object('passos1', (v_e ->> 'passos1')::int + public._agenda_viagem_extra(v_7d_vi ->> 'tipo', (v_7d_vi ->> 'extra_por')::int, (v_e ->> 'passos1')::int)) else '{}'::jsonb end;
        end if;
      end if;
    end if;
    -- FASE 7d: fim
    v_fila := v_fila || v_e;
  end loop;

  -- A ordem: (classe, atrasar, prioridade do dono, razão crítica, sinal pago, aprovação, número, id).
  select coalesce(jsonb_agg(x.e || jsonb_build_object('ordem', x.rn) order by x.rn), '[]'::jsonb) into v_fila
    from (select e, row_number() over (order by (e ->> 'classe')::int, (e ->> 'atrasar')::boolean, (e ->> 'prio')::int nulls last,
                                                (e ->> 'razao')::numeric nulls last, (e ->> 'sinal')::boolean desc,
                                                (e ->> 'aprovada_em')::date nulls last, e ->> 'numero' collate "C", e ->> 'os') as rn
            from jsonb_array_elements(v_fila) e) x;
  select coalesce(jsonb_object_agg(e ->> 'i', e), '{}'::jsonb) into v_ent from jsonb_array_elements(v_fila) e;

  v_par := jsonb_build_object('wip', cf.wip_max, 'imax', cf.interrupcoes_max, 'inicios', cf.inicios_tentados_du,
                              'semana', p_escopo = 'semana', 'jan_de', v_de - v_ini + 1, 'jan_ate', v_ate - v_ini + 1,
                              'acima', v_acima);
  -- FASE 7b: (7b P4) os parâmetros do sábado (modo e política) e da dupla (modo; a espera: ligado, dupla_espera_max_du dias úteis;
  -- em teste, 0 — a dupla só entra quando não termina depois do bloco de 1 pessoa, d8), só com os modos da 7b
  if cf.modo_sabado <> 'desligado' or cf.modo_dupla <> 'desligado' then
    v_par := v_par || jsonb_build_object('sab_modo', cf.modo_sabado, 'sab_politica', cf.sabado_manha, 'dupla_modo', cf.modo_dupla,
                                         'dupla_espera', case when cf.modo_dupla = 'ligado' then cf.dupla_espera_max_du else 0 end);
  end if;
  -- FASE 7b: fim
  -- FASE 7c: (7c P2, §5.2 2) os parâmetros da 7c, sempre (o encaixe lê a presença deles como "grave o critério"): hab_modo (os
  -- filtros 3 e 4 e a ordem nova, só ligado), lid_modo (o filtro 5 e a troca avisada, só ligado), os níveis, o fechamento que cobre
  -- o último dia e a espera pelo responsável; o v_parh herda
  v_par := v_par || jsonb_build_object('hab_modo', (cf.modo_habilidade = 'ligado')::int, 'lid_modo', (cf.modo_lider = 'ligado')::int,
                                       'n', jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                                                               'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura,
                                                               'par', cf.habilidade_nivel_par),
                                       'fcobre', cf.habilidade_fechamento_cobre, 'lid_espera', cf.lider_espera_max_du);
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4 3, R6.8-3) mesmo_dia, com modo_mesmo_local ligado; troca, ligado e na temporada (o mês de p_hoje em temporada_meses, AG7-20).
  -- Chave AUSENTE fora disso: agenda_propostas.parametros e o M1 comparam
  if v_7d_ml then
    v_par := v_par || jsonb_build_object('mesmo_dia', true);
    if extract(month from p_hoje)::smallint = any (cf.temporada_meses) then
      v_par := v_par || jsonb_build_object('troca', true);
    end if;
  end if;
  -- FASE 7d: fim
  v_parh := v_par || jsonb_build_object('semana', false);

  -- ── 5. O encaixe e a sobrecarga (o banco nunca escolhe quem atrasa) ──
  for v_tentativa in 1 .. 3 loop
    -- (quem ficou sem saída na volta anterior sai da fila: fica fora, sem encaixe)
    v_r0 := public._agenda_encaixar(v_ctx,
              (select jsonb_agg(case when (e ->> 'i')::int = any (v_sem_q) then e || '{"tirar": true}'::jsonb else e end)
                 from jsonb_array_elements(v_fila) e), v_par);
    -- o que é crítico em cada compromisso colocado
    v_crit := '{}'::jsonb;
    for v_b in select e from jsonb_array_elements(v_r0 -> 'colocadas') e where e ->> 'tipo' = 'compromisso' loop
      v_e := v_ent -> (v_b ->> 'i');
      continue when v_e ? 'fixar_de';
      v_os := (v_e ->> 'os')::uuid;
      v_ini_x := v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1;
      v_fim_x := greatest(v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1, (v_e ->> 'kept_max')::date);
      v_canc_os := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c where (c ->> 'os')::uuid = v_os);
      v_ini_antes := (select min((c ->> 'dia')::date) from jsonb_array_elements(v_canc) c
                       where (c ->> 'os')::uuid = v_os and c ->> 'tipo' <> 'reserva');
      v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_x, v_ini_x, p_hoje, v_canc_os, '{}');
      -- FASE 7: (7a P8, spec §3.2 e §5.8) a zona travada (a regra zona_travada): a criticidade de novo, agora sabendo o que fica
      -- fora da conta do dia já avisado — o que não pode mais acontecer, o resto do meio-dia dele e o que volta igual neste
      -- encaixe (_agenda_zona_fora; o fixado pelo dono nunca fica fora: a regra dele não muda).
      if public._agenda_gestor_regra('zona_travada') then
        v_f7_fora := public._agenda_zona_fora(v_canc, v_os, public._agenda_alocs_do_bloco(v_ctx, v_b));
        v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_x, v_ini_x, p_hoje, v_canc_os,
                                             v_f7_fora);
      end if;
      -- FASE 7: fim
      if v_tipo is not null then
        v_crit := v_crit || jsonb_build_object(v_b ->> 'i', jsonb_build_object('tipo', v_tipo, 'fim', v_fim_x, 'ini', v_ini_x));
      end if;
    end loop;
    -- as críticas ainda sem decisão
    v_xnc := array(select k::int from jsonb_each(v_crit) t(k, x)
                    where x ->> 'tipo' = 'nao_cabe' and v_decisao is null
                      and not ((v_ent -> k ->> 'os')::uuid = any (v_aceitar)) and not (k::int = any (v_sem_q)) order by 1);
    v_xoc := array(select k::int from jsonb_each(v_crit) t(k, x)
                    where x ->> 'tipo' <> 'nao_cabe' and v_decisao is null
                      and not ((v_ent -> k ->> 'os')::uuid = any (v_aceitar)) and not (k::int = any (v_sem_q)) order by 1);
    -- quem X empurraria: as da classe 2 colocadas antes dela, novas e sem fixado, as mais próximas
    v_cands := '{}'::jsonb;
    foreach v_x in array v_xnc loop
      v_cands := v_cands || jsonb_build_object(v_x::text, coalesce((
        select jsonb_agg(q.i order by q.ordem desc)
          from (select (b ->> 'i')::int as i, (v_ent -> (b ->> 'i') ->> 'ordem')::int as ordem
                  from jsonb_array_elements(v_r0 -> 'colocadas') b
                 where b ->> 'tipo' = 'compromisso'
                   and (v_ent -> (b ->> 'i') ->> 'classe')::int = 2 and not (v_ent -> (b ->> 'i')) ? 'fixar_de'
                   and not (v_ent -> (b ->> 'i') ->> 'tem_fixada')::boolean and v_ent -> (b ->> 'i') ->> 'fim_antes' is null
                   and (v_ent -> (b ->> 'i') ->> 'ordem')::int < (v_ent -> v_x::text ->> 'ordem')::int
                   and not ((b ->> 'i')::int = any (v_xnc || v_xoc))
                   -- (na 2ª volta, só as que deram opção: quem não faz X caber não fica esperando a decisão)
                   and (v_usadas is null or coalesce(v_usadas -> v_x::text, '[]'::jsonb) @> to_jsonb((b ->> 'i')::int))
                 order by 2 desc limit c_candidatas) q), '[]'::jsonb));
    end loop;
    v_h := array(select distinct x from (select unnest(v_xnc || v_xoc) as x
                                          union select (j)::int from jsonb_each(v_cands) t(k, v), jsonb_array_elements_text(v) j) u
                  order by 1);
    exit when cardinality(v_h) = 0;

    -- O que é publicado sem esperar sai desta mesma rodada (as reservas foram depois de todos os compromissos, e não
    -- tomam o lugar de quem espera a decisão); quem espera fica como item crítico (X, a que não cabe, sai).
    v_rf := v_r0;
    v_ctxf := public._agenda_ctx_com(v_ctx,
                (select coalesce(jsonb_agg(b), '[]'::jsonb) from jsonb_array_elements(v_r0 -> 'colocadas') b
                  where not ((b ->> 'i')::int = any (v_h) and b ->> 'tipo' = 'compromisso')));
    -- a decisão vai encontrar a grade já com o resto publicado: as opções são simuladas sobre ela
    v_base := public._agenda_encaixar(v_ctxf,
                (select jsonb_agg(e) from jsonb_array_elements(v_fila) e where (e ->> 'i')::int = any (v_h)), v_parh);
    v_perg := '[]'::jsonb;
    v_n := cardinality(v_sem_q);
    foreach v_x in array v_xnc || v_xoc loop
      v_e := v_ent -> v_x::text;
      v_os := (v_e ->> 'os')::uuid;
      v_tipo := v_crit -> v_x::text ->> 'tipo';
      v_xb := (select b from jsonb_array_elements(v_base -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso');
      v_fim_x := case when v_xb is null then null
                      else greatest(v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1, (v_e ->> 'kept_max')::date) end;
      v_opc := '[]'::jsonb;
      if v_tipo = 'nao_cabe' then
        if v_fim_x is not null then
          v_opc := v_opc || jsonb_build_object('n', 1, 'os', v_os, 'atraso_dito', public.agenda_du_entre((v_e ->> 'precisa')::date, v_fim_x),
                     'sem_data', false, 'atraso_du', public.agenda_du_entre((v_e ->> 'precisa')::date, v_fim_x), 'numero', v_e ->> 'numero',
                     'texto', format('%s atrasa: termina %s em vez de %s', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                                     public._dia_curto((v_e ->> 'precisa')::date)),
                     'efeito', jsonb_build_object('restricoes', jsonb_build_object('aceitar_atraso', jsonb_build_array(v_os))),
                     'espera', jsonb_build_object(v_os::text, v_fim_x));
        end if;
        for v_c in select (j)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) j loop
          v_sim := public._agenda_encaixar(v_ctxf,
                     (select jsonb_agg(case when (e ->> 'i')::int = v_c
                                            then e || jsonb_build_object('ordem', (e ->> 'ordem')::int + c_fim_da_classe) else e end)
                        from jsonb_array_elements(v_fila) e where (e ->> 'i')::int = any (v_h)), v_parh);
          v_xb := (select b from jsonb_array_elements(v_sim -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso');
          v_cb := (select b from jsonb_array_elements(v_sim -> 'colocadas') b where (b ->> 'i')::int = v_c and b ->> 'tipo' = 'compromisso');
          continue when v_xb is null or v_cb is null
                     or v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1 > (v_e ->> 'precisa')::date;
          v_ini_c := v_ini + ((v_cb ->> 'ini')::int + 1) / 2 - 1;
          v_fim_c := v_ini + ((v_cb ->> 'fim')::int + 1) / 2 - 1;
          v_b := (select b from jsonb_array_elements(v_base -> 'colocadas') b where (b ->> 'i')::int = v_c and b ->> 'tipo' = 'compromisso');
          v_opc := v_opc || jsonb_build_object('n', jsonb_array_length(v_opc) + 1, 'os', v_ent -> v_c::text -> 'os', 'c', v_c,
                     'atraso_dito', case when v_ent -> v_c::text ->> 'precisa' is null then 0
                                         else greatest(public.agenda_du_entre((v_ent -> v_c::text ->> 'precisa')::date, v_fim_c), 0) end,
                     'sem_data', v_ent -> v_c::text ->> 'precisa' is null,
                     'atraso_du', case when v_b is null then 0
                                       else greatest(public.agenda_du_entre(v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1, v_fim_c), 0) end,
                     'numero', v_ent -> v_c::text ->> 'numero',
                     'texto', format('%s passa para %s (%s)', public._agenda_rotulo_da_os((v_ent -> v_c::text ->> 'os')::uuid),
                                     public._agenda_dias_texto(array(select distinct v_ini + (h - 1) / 2
                                                                       from unnest(public._agenda_ints(v_cb -> 'h')) h)),
                                     case when v_ent -> v_c::text ->> 'precisa' is null then 'sem data dita pelo cliente'
                                          else 'precisa até ' || public._dia_curto((v_ent -> v_c::text ->> 'precisa')::date) end),
                     'efeito', jsonb_build_object('restricoes', jsonb_build_object('atrasar', jsonb_build_array(v_ent -> v_c::text -> 'os'))),
                     'espera', jsonb_build_object(v_os::text, v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1,
                                                  v_ent -> v_c::text ->> 'os', v_fim_c));
          exit when jsonb_array_length(v_opc) >= 4;
        end loop;
      elsif v_fim_x is not null then
        v_opc := v_opc || jsonb_build_object('n', 1, 'os', v_os, 'atraso_dito', 0, 'sem_data', false, 'atraso_du', 0, 'numero', v_e ->> 'numero',
                   'texto', format('Sigo: %s termina %s em vez de %s', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                                   public._dia_curto((v_e ->> 'fim_antes')::date)),
                   'efeito', jsonb_build_object('restricoes', jsonb_build_object('aceitar_atraso', jsonb_build_array(v_os))),
                   'espera', jsonb_build_object(v_os::text, v_fim_x));
      end if;
      if jsonb_array_length(v_opc) = 0 then
        -- sem saída nenhuma: não é pergunta (fica fora, sem encaixe); a próxima volta refaz sem ela na espera
        v_sem_q := v_sem_q || v_x;
        continue;
      end if;
      if jsonb_array_length(v_opc) = 1 then
        v_opc := v_opc || jsonb_build_object('n', 2, 'os', v_os, 'atraso_dito', null, 'sem_data', false, 'atraso_du', null,
                   'numero', v_e ->> 'numero',
                   'texto', format('Deixo o %s fora do plano por enquanto', public._agenda_nome_curto(v_e ->> 'cliente_curto')),
                   'efeito', jsonb_build_object('restricoes', jsonb_build_object('tirar', jsonb_build_array(v_os))),
                   'espera', '{}'::jsonb);
      end if;
      -- a recomendação: o menor atraso sobre datas ditas; no empate, quem não tem data dita, o menor atraso, o número
      if v_tipo = 'nao_cabe' then
        select (o ->> 'n')::int into v_rec from jsonb_array_elements(v_opc) o
         where o ->> 'atraso_dito' is not null
         order by (o ->> 'atraso_dito')::int, (o ->> 'sem_data')::boolean desc, (o ->> 'atraso_du')::int, o ->> 'numero' collate "C"
         limit 1;
        v_rec := coalesce(v_rec, 1);
        v_q := v_opc -> (v_rec - 1);
        v_rec_txt := case when (v_q ->> 'sem_data')::boolean
                            then format('o %s não tem data dita pelo cliente', public._agenda_nome_curto((select cl.name from public.service_orders so
                                          join public.clients cl on cl.id = so.client_id where so.id = (v_q ->> 'os')::uuid)))
                          when v_rec = 1 then format('é o menor atraso (%s)', public._agenda_plural((v_q ->> 'atraso_du')::int, 'dia útil', 'dias úteis'))
                          else 'é o menor atraso sobre o que o cliente pediu' end;
        v_txt := format('Não cabe tudo até %s. Qual aceita atrasar? %s. Recomendo a %s: %s.',
                        public._dia_curto((v_e ->> 'precisa')::date),
                        (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int) from jsonb_array_elements(v_opc) o),
                        v_rec, v_rec_txt);
      else
        v_rec := 1;
        v_rec_txt := case v_tipo
          when 'atraso_longo' then 'Recomendo seguir e você ligar para o cliente hoje'
          when 'segundo_atraso' then 'É o 2º atraso desta OS: recomendo seguir e você ligar para o cliente hoje'
          when 'remarcar_confirmado' then 'O cliente tinha confirmado o dia: recomendo seguir e você ligar para ele hoje'
          else 'Você tinha fixado o dia, que não dá mais: recomendo seguir no novo dia' end;
        -- FASE 7: (7a P3) a recomendação das críticas da zona travada do gestor (P8: o dia que a equipe já recebeu na ficha e o
        -- que o cliente já ouviu); inertes até lá (_agenda_criticidade ainda não dá esses tipos)
        if v_tipo = 'dia_avisado' then
          v_rec_txt := 'A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia';
        elsif v_tipo = 'dia_prometido' then
          v_rec_txt := 'É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje';
        end if;
        -- FASE 7: fim
        v_txt := format('%s só dá para terminar em %s, %s depois do que estava no plano. 1) %s; 2) %s. %s.',
                        public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                        public._agenda_plural(v_fim_x - (v_e ->> 'fim_antes')::date, 'dia', 'dias'),
                        v_opc -> 0 ->> 'texto', v_opc -> 1 ->> 'texto', v_rec_txt);
      end if;
      v_chave := format('%s:%s:%s', v_tipo, v_os, v0);
      v_perg := v_perg || jsonb_build_object(
        'tipo', v_tipo, 'chave', v_chave, 'service_order_id', v_os,
        'os_ids', (select jsonb_agg(v_ent -> j::text -> 'os' order by j) from unnest(array[v_x] || coalesce(
                     array(select (k)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) k), '{}'::int[])) j),
        'texto', left(v_txt, 600), 'opcoes', v_opc, 'recomendacao', v_rec, 'recomendacao_texto', left(v_rec_txt, 300),
        'perda_em', (select min(v_ini + ((b ->> 'ini')::int + 1) / 2 - 1) from jsonb_array_elements(v_base -> 'colocadas') b
                      where (b ->> 'i')::int = any (array[v_x] || coalesce(
                        array(select (k)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) k), '{}'::int[]))),
        'x', v_x);
    end loop;
    -- quem ficou sem saída sai da espera e a conta é refeita
    continue when cardinality(v_sem_q) <> v_n;
    -- as que não fazem X caber não ficam esperando a decisão: a conta é refeita só com as que deram opção (uma vez)
    if v_usadas is null and exists (
         select 1 from jsonb_each(v_cands) t(k, v), jsonb_array_elements_text(t.v) j
          where not exists (select 1 from jsonb_array_elements(v_perg) q, jsonb_array_elements(q -> 'opcoes') o
                             where (q ->> 'x')::int = t.k::int and (o ->> 'c')::int = j::int)) then
      select coalesce(jsonb_object_agg(q ->> 'x', coalesce((select jsonb_agg((o ->> 'c')::int) from jsonb_array_elements(q -> 'opcoes') o
                                                             where o ? 'c'), '[]'::jsonb)), '{}'::jsonb)
        into v_usadas from jsonb_array_elements(v_perg) q;
      continue;
    end if;
    exit;
  end loop;
  if cardinality(v_h) = 0 then
    v_xnc := '{}';
    v_xoc := '{}';
    v_perg := '[]'::jsonb;
    v_rf := v_r0;
    v_ctxf := public._agenda_ctx_com(v_ctx, v_rf -> 'colocadas');
    v_base := jsonb_build_object('colocadas', '[]'::jsonb);
  end if;

  -- ── 6. Os itens: o que sai, o que entra, o que espera a decisão ──
  -- (a) o que sai (a violação, o resto do meio-dia, o pedido do dono)
  v_itens := v_itens || coalesce((
    select jsonb_agg(jsonb_build_object(
             'op', 'cancelar', 'os', g.os, 'numero', g.numero, 'cliente_curto', g.cliente_curto, 'tipo', g.tipo,
             'motivo', g.motivo, 'violada', g.violada, 'alocacoes', g.alocs, 'de', g.de, 'ate', g.ate,
             'critica', null, 'decisao', v_decisao, 'aplicado', false,
             'texto', format('%s: sai %s — %s.', public._agenda_rotulo_da_os(g.os), public._agenda_dias_texto(g.dias),
                             case g.motivo when 'pessoa' then 'quem ia não está mais livre' when 'material' then 'o material não chega a tempo'
                                           when 'cliente' then 'o cliente ou o bem não está liberado' when 'os_saiu' then 'a OS saiu da carteira'
                                           when 'condicao_vencida' then 'a condição da reserva venceu' when 'dono' then 'você pediu outro dia'
                                           when 'espera' then coalesce('você pôs em espera até ' || public._dia_curto(
                                             (select pl.congelada_ate from public.os_planejamento pl where pl.service_order_id = g.os)),
                                             'você pôs em espera')
                                           else 'replanejado junto' end))
             order by g.numero, g.os, g.motivo)
      from (select (c ->> 'os')::uuid as os, min(v_info -> (c ->> 'os') -> 'pront' ->> 'numero') as numero,
                   min(v_info -> (c ->> 'os') -> 'pront' ->> 'cliente_curto') as cliente_curto,
                   case when bool_and(c ->> 'tipo' = 'reserva') then 'reserva' else min(c ->> 'tipo') end as tipo,
                   c ->> 'motivo' as motivo, bool_or((c ->> 'violada')::boolean) as violada,
                   jsonb_agg(jsonb_build_object('alocacao_id', c -> 'alocacao_id', 'payee_id', c -> 'payee_id',
                               'nome', (select public._agenda_nome_curto(py.name) from public.payees py where py.id = (c ->> 'payee_id')::uuid),
                               'dia', c -> 'dia', 'turno', c -> 'turno', 'presenca', c -> 'presenca', 'estado', c -> 'estado',
                               'fixado_por', c -> 'fixado_por')
                             order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'payee_id') as alocs,
                   array_agg((c ->> 'dia')::date) as dias, min((c ->> 'dia')::date) as de, max((c ->> 'dia')::date) as ate
              from jsonb_array_elements(v_canc) c
             group by (c ->> 'os')::uuid, c ->> 'motivo') g), '[]'::jsonb);
  -- FASE 7c: (7c P2, §5.2 4, §6.8) o que sai pela violação habilidade (a do P3: a equipe do meio-dia não tem quem o serviço pede) diz
  -- o porquê, no lugar do "replanejado junto"
  if exists (select 1 from jsonb_array_elements(v_itens) i where i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'habilidade') then
    select coalesce(jsonb_agg(case when i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'habilidade'
                                   then i || jsonb_build_object('texto', format('%s: sai %s — a equipe do dia não tinha quem o serviço pede.',
                                          public._agenda_rotulo_da_os((i ->> 'os')::uuid),
                                          public._agenda_dias_texto(array(select (a ->> 'dia')::date from jsonb_array_elements(i -> 'alocacoes') a))))
                                   else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
  end if;
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4 3, §6.2) o que sai pela violação local diz o porquê, no lugar do "replanejado junto"
  if exists (select 1 from jsonb_array_elements(v_itens) i where i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'local') then
    select coalesce(jsonb_agg(case when i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'local'
                                   then i || jsonb_build_object('texto', format('%s: sai %s — o local não recebe a equipe nesse dia.',
                                          public._agenda_rotulo_da_os((i ->> 'os')::uuid),
                                          public._agenda_dias_texto(array(select (a ->> 'dia')::date from jsonb_array_elements(i -> 'alocacoes') a))))
                                   else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
  end if;
  -- FASE 7d: fim
  -- (b) a reserva que virou compromisso nesta proposta
  v_itens := v_itens || coalesce((
    select jsonb_agg(jsonb_build_object(
             'op', 'cancelar', 'os', g.os, 'numero', v_ent -> g.i ->> 'numero', 'cliente_curto', v_ent -> g.i ->> 'cliente_curto',
             'tipo', 'reserva', 'motivo', 'promovida', 'violada', false, 'alocacoes', g.alocs, 'de', g.de, 'ate', g.ate,
             'critica', null, 'decisao', v_decisao, 'aplicado', false,
             'texto', format('%s: a reserva vira compromisso.', public._agenda_rotulo_da_os(g.os)))
             order by v_ent -> g.i ->> 'numero')
      from (select b ->> 'i' as i, (v_ent -> (b ->> 'i') ->> 'os')::uuid as os,
                   (select jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                     'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca, 'estado', a.estado, 'fixado_por', a.fixado_por)
                                     order by a.dia, a.turno = 'tarde', a.payee_id)
                      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                     where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid and a.estado in ('publicada', 'fixada')
                       and a.tipo = 'reserva' and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje
                       and not (a.id = any (v_ign))) as alocs,
                   (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid
                       and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje) as de,
                   (select max(a.dia) from public.agenda_alocacoes a where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid
                       and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje) as ate
              from jsonb_array_elements(v_rf -> 'colocadas') b
             where b ->> 'tipo' = 'compromisso' and coalesce((b ->> 'na_janela')::boolean, true)
               and (v_ent -> (b ->> 'i') ->> 'tem_reserva')::boolean and not ((b ->> 'i')::int = any (v_h))) g
     where g.alocs is not null), '[]'::jsonb);
  -- (c) o que entra: publicável sem esperar, ou (d) esperando a decisão (a X que não cabe sai da proposta)
  for v_b in
    select b || jsonb_build_object('espera', (b ->> 'i')::int = any (v_h) and b ->> 'tipo' = 'compromisso')
      from jsonb_array_elements(v_rf -> 'colocadas') b
     where coalesce((b ->> 'na_janela')::boolean, true)
       and not ((b ->> 'i')::int = any (v_xnc) and b ->> 'tipo' = 'compromisso')
  loop
    v_e := v_ent -> (v_b ->> 'i');
    v_os := (v_e ->> 'os')::uuid;
    v_ini_x := v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1;
    v_fim_x := v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1;
    v_fim_dep := greatest(v_fim_x, (v_e ->> 'kept_max')::date);
    v_canc_os := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c where (c ->> 'os')::uuid = v_os);
    v_ini_antes := (select min((c ->> 'dia')::date) from jsonb_array_elements(v_canc) c
                     where (c ->> 'os')::uuid = v_os and c ->> 'tipo' <> 'reserva');
    v_tipo := case when v_b ->> 'tipo' = 'reserva' or v_e ? 'fixar_de' then null
                   else public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_dep, v_ini_x, p_hoje,
                                                   v_canc_os, '{}') end;
    -- FASE 7: (7a P8) a zona travada, como no encaixe acima (o que espera a decisão de outra OS segue a de antes)
    if v_b ->> 'tipo' <> 'reserva' and not v_e ? 'fixar_de' and not coalesce((v_b ->> 'espera')::boolean, false)
       and public._agenda_gestor_regra('zona_travada') then
      v_f7_fora := public._agenda_zona_fora(v_canc, v_os, public._agenda_alocs_do_bloco(v_ctx, v_b));
      v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_dep, v_ini_x, p_hoje,
                                           v_canc_os, v_f7_fora);
    end if;
    -- FASE 7: fim
    -- quem espera a decisão de uma X: o tipo dela e a chave da pergunta
    v_chave := null;
    if (v_b ->> 'espera')::boolean then
      select q ->> 'chave', coalesce(v_tipo, q ->> 'tipo') into v_chave, v_tipo from jsonb_array_elements(v_perg) q
       where q -> 'os_ids' @> jsonb_build_array(v_os) order by q ->> 'chave' limit 1;
    elsif v_tipo is not null and v_decisao is null and not (v_os = any (v_aceitar)) then
      -- crítico sem pergunta (não deveria acontecer: a pergunta foi feita acima); fica esperando
      v_chave := format('%s:%s:%s', v_tipo, v_os, v0);
    end if;
    -- O pedido do dono num dia antes de o material estar garantido: fica (a decisão é dele), com o aviso na frase.
    v_aviso := case when v_e ? 'fixar_de' and v_b ->> 'tipo' <> 'reserva'
                    then public._agenda_aviso_do_material(v_info -> v_os::text -> 'pront', v_e ->> 'condicao_tipo', v_e ->> 'texto', v_ini_x) end;
    -- FASE 7c: (7c P2, §5.2 3, §3.1-3) com modo_habilidade ligado, onde o dono disse quem vai (o pedido com pessoa, a equipe dita), a
    -- palavra dele vale e o item ganha o aviso, ao lado do de material ("— mas João iria sozinho, e o último dia pede quem instala
    -- sozinho com 220 V ou banco de bateria")
    if cf.modo_habilidade = 'ligado' and v_b ->> 'tipo' <> 'reserva'
       and (v_e ? 'fixar_de' or coalesce((v_info -> v_os::text -> 'meios' ->> 'equipe_dita')::boolean, false)) then
      v_aviso := nullif(concat_ws('; ', v_aviso, public._agenda_aviso_da_habilidade(v_os, public._agenda_alocs_do_bloco(v_ctx, v_b), p_hoje)), '');
    end if;
    -- FASE 7c: fim
    v_txt := case
      when v_b ->> 'tipo' = 'reserva' then
        format('%s: %s, %s%s.',
               case v_b ->> 'reserva_de' when 'patio' then 'Reserva no pátio' when 'teto' then 'Reserva (acima da carga)' else 'Reserva' end
                 || ' ' || public._agenda_rotulo_da_os(v_os),
               public._agenda_faixa_texto(v_ini_x, case when (v_b ->> 'ini')::int % 2 = 1 then 'manha' else 'tarde' end,
                                          v_fim_x, case when (v_b ->> 'fim')::int % 2 = 1 then 'manha' else 'tarde' end),
               public._agenda_pessoas_texto(public._agenda_alocs_do_bloco(v_ctx, v_b), v_dono), '')
      else
        format('%s%s: %s, %s%s.', public._agenda_rotulo_da_os(v_os),
               case v_e ->> 'tipo_os' when 'diagnostico' then ', diagnóstico' when 'comissionamento' then ', comissionamento' else '' end,
               public._agenda_dias_texto(array(select distinct (a ->> 'dia')::date
                                                 from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a)),
               public._agenda_pessoas_texto(public._agenda_alocs_do_bloco(v_ctx, v_b), v_dono),
               coalesce(' — mas ' || v_aviso, '')) end;
    -- FASE 7d: (correção O15) o feriado do município que o bloco atravessa diz o motivo, como o nacional ("sex 20 é Consciência Negra"): "ter 20 é feriado em Balneário Camboriú".
    -- local_txt só existe com o calendário ligado: sem ele, nenhuma leitura
    if v_e ? 'local_txt' and v_b ->> 'tipo' <> 'reserva' then
      v_7d_dt := public._agenda_dias_texto(array(select distinct (a ->> 'dia')::date from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a));
      v_7d_mf := public._agenda_feriado_do_bloco(v_e -> 'local_txt', v_ini, v_ini_x, v_fim_x);
      if v_7d_mf is not null then
        v_txt := replace(v_txt, ': ' || v_7d_dt || ',', ': ' || case when right(v_7d_dt, 1) = ')' then left(v_7d_dt, -1) || ', ' || v_7d_mf || ')'
                                                                     else v_7d_dt || ' (' || v_7d_mf || ')' end || ',');
      end if;
    end if;
    -- FASE 7d: fim
    -- FASE 7: (7a P3, D7-1) o compromisso marcado pela estimativa do orçamento (a fonte 'orcamento' de agenda_meios_da_os, que
    -- só existe com a regra estimativa) diz isso no fim: "… com Roberto e João (estimativa minha: 6 dias)."
    if v_e ->> 'fonte' = 'orcamento' and v_b ->> 'tipo' <> 'reserva' and right(v_txt, 1) = '.' then
      v_txt := left(v_txt, -1) || format(' (estimativa minha: %s).', public._agenda_dias((v_e ->> 'dias')::numeric));
    end if;
    -- FASE 7: fim
    -- FASE 7b: (7b P4, §6.3, R4.3(a)(3)) ligado: o compromisso com o sábado diz qual e por quê (" — com sáb 14/11 de manhã (Rafael
    -- se ofereceu), para cumprir o prazo de qua 18/11."); o bloco de 1 pessoa da dupla inferida diz em que meios-dias a tarefa pede
    -- 2 e o que fazer (" Nos 2 primeiros meios-dias (qua 04/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex
    -- está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem qua 04/11)."). Em teste, nada aqui (a linha "Em teste" abaixo).
    if v_b ? 'sabado' and right(v_txt, 1) = '.' then
      select array_agg(distinct (a ->> 'dia')::date order by (a ->> 'dia')::date) into v_7b_dias
        from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a
       where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno';
      v_7b_nomes := array(select y.x from (select a ->> 'nome' as x, min(o) as o
                                             from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) with ordinality t(a, o)
                                            where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' group by 1) y
                           order by y.o);
      v_txt := left(v_txt, -1) || format(' — com %s de manhã (%s %s)%s.', public._agenda_dias_texto(v_7b_dias),
                 public._agenda_lista(v_7b_nomes), case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end,
                 case when v_e ? 'prazo' then ', para cumprir o prazo de ' || public._dia_curto((v_e ->> 'prazo')::date) else '' end);
    end if;
    if v_b ? 'dupla_falta' and cf.modo_dupla = 'ligado' and jsonb_array_length(v_b -> 'dupla_falta') > 0 then
      if v_7b_tec is null then
        v_7b_tec := public._agenda_tecnicos_da_grade(p_hoje);
      end if;
      -- os meios-dias de cada parte: "qua 04/11, manhã e tarde", "qua 04/11 de manhã"
      select public._agenda_lista(array(
               select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                     when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                 from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                         from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' in ('inicio', 'todos')) z
                group by z.d order by z.d)),
             public._agenda_lista(array(
               select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                     when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                 from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                         from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' = 'fim') z
                group by z.d order by z.d))
        into v_7b_x, v_7b_y;
      v_7b_n := (select count(*)::int from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' = 'inicio');
      v_7b_z := case
        when coalesce((v_e ->> 'dupla_todos')::boolean, false)
          then format('O serviço todo pede 2 pessoas (%s) e %s: vai com 1 pessoa; se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      coalesce(v_e ->> 'dupla_rot_todos', 'o orçamento previu 2 técnicos'),
                      case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre' else public._agenda_tecnicos_frase(v_7b_tec) end,
                      public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1))
        when v_7b_x <> '' and v_7b_y <> ''
          then format('%s (%s) %s e %s (%s) %s pedem 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end, v_7b_x,
                      v_e ->> 'dupla_rot_ini',
                      case when jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n = 1 then 'no último meio-dia'
                           else format('nos %s últimos meios-dias', jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n) end, v_7b_y,
                      v_e ->> 'dupla_rot_fim',
                      case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_7b_tec) end,
                      public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1))
        else format('%s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                    case when v_7b_x <> '' then case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end
                         when jsonb_array_length(v_b -> 'dupla_falta') = 1 then 'No último meio-dia'
                         else format('Nos %s últimos meios-dias', jsonb_array_length(v_b -> 'dupla_falta')) end,
                    case when v_7b_x <> '' then v_7b_x else v_7b_y end,
                    case when v_7b_x <> '' then v_e ->> 'dupla_rot_ini' else v_e ->> 'dupla_rot_fim' end,
                    case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_7b_tec) end,
                    public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1)) end;
      -- (correção da revisão da 7b, achado 23) o exemplo diz todos os dias em que falta a 2ª pessoa, não só o 1º ("ex.: Mateus vem
      -- qua 18 e qui 19/11"): quem seguisse o exemplo ao pé da letra deixava os outros meios-dias sem a 2ª pessoa
      v_7bc_dias := array(select distinct v_ini + ((f ->> 'h')::int + 1) / 2 - 1 from jsonb_array_elements(v_b -> 'dupla_falta') f order by 1);
      if cardinality(v_7bc_dias) > 1 then
        v_7b_z := replace(v_7b_z, format('(ex.: Mateus vem %s).', public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1)),
                          format('(ex.: Mateus vem %s).', regexp_replace(public._agenda_dias_texto(v_7bc_dias), ' \([^()]*\)$', '')));
      end if;
      -- (correção da revisão da 7b: fim)
      -- o texto da ação (agenda_acoes.texto, até 400) junta os itens da mesma OS: com a frase da dupla, o item fica em até 320 — sem
      -- caber a frase inteira, a curta (sem os dias e sem quem está na equipe)
      if char_length(v_txt) + 1 + char_length(v_7b_z) > 320 then
        v_7b_n2 := jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n;
        v_7b_z := case
          when coalesce((v_e ->> 'dupla_todos')::boolean, false) then 'O serviço todo pede 2 pessoas: se chamar um ajudante, me diga os dias dele.'
          when v_7b_x <> '' and v_7b_y <> ''
            then format('%s e %s pedem 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                        case when v_7b_n = 1 then 'O primeiro meio-dia' else format('Os %s primeiros meios-dias', v_7b_n) end,
                        case when v_7b_n2 = 1 then 'o último' else format('os %s últimos', v_7b_n2) end)
          when v_7b_x <> ''
            then format('%s %s pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                        case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end, v_e ->> 'dupla_rot_ini')
          else format('%s %s pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                      case when v_7b_n2 = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_n2) end, v_e ->> 'dupla_rot_fim') end;
      end if;
      v_txt := public._agenda_corta(v_txt || ' ' || v_7b_z, 320);
    end if;
    -- FASE 7b: fim
    v_itens := v_itens || jsonb_build_object(
      'op', 'criar', 'os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
      'tipo', case when v_b ->> 'tipo' = 'reserva' then 'reserva' else v_e ->> 'tipo_os' end,
      'reserva_de', v_b ->> 'reserva_de', 'alocacoes', public._agenda_alocs_do_bloco(v_ctx, v_b),
      'de', v_ini_x, 'ate', v_fim_x, 'fim_antes', v_e ->> 'fim_antes', 'fim_depois', v_fim_dep,
      'atraso_du', case when v_b ->> 'tipo' <> 'reserva' and v_e ->> 'fim_antes' is not null and v_fim_dep > (v_e ->> 'fim_antes')::date
                        then public.agenda_du_entre((v_e ->> 'fim_antes')::date, v_fim_dep) end,
      'condicao_tipo', case when v_b ->> 'reserva_de' = 'condicionada' then v_e ->> 'condicao_tipo' end,
      'critica', v_tipo, 'pergunta_chave', v_chave, 'decisao', v_decisao, 'espera', (v_b ->> 'espera')::boolean,
      'interrupcoes', (v_b ->> 'int')::int, 'meios_do_dono', (v_b ->> 'md')::int, 'fonte', v_e ->> 'fonte', 'dias', v_e -> 'dias',
      'evento_real', (v_e ->> 'evento_real')::boolean, 'fixar_dono', v_e ? 'fixar_de', 'aviso_material', v_aviso,
      'abre', (v_e ->> 'abre')::boolean and v_b ->> 'tipo' <> 'reserva', 'fecha', (v_e ->> 'fecha')::boolean and v_b ->> 'tipo' <> 'reserva',
      'motivos', to_jsonb(array_remove(array[
         case when v_e ->> 'classe' = '1' and not v_e ? 'fixar_de' then 'em andamento ou fixada' end,
         case when v_e ? 'fixar_de' then 'você pediu' end,
         case when (v_e ->> 'evento_real')::boolean then 'replanejado por um imprevisto de hoje ou amanhã' end,
         case when v_b ->> 'tipo' <> 'reserva' then v_e ->> 'texto' end,
         case when v_b ->> 'reserva_de' = 'teto' then 'não coube na carga de ' || public._agenda_num(cf.carga_max * 100, 0) || '%' end,
         case when v_b ->> 'reserva_de' = 'condicionada' then v_e ->> 'texto' end,
         case when v_b ->> 'reserva_de' = 'patio' then 'adiantar no pátio enquanto o bem está fora' end], null)),
      'texto', v_txt, 'aplicado', false);
    -- FASE 7d: (7d P4, §5.4 3, §6.2, R6.8-3) o item que entra ganha local_texto, suposicoes, viagem e imax_os (só com os modos ligados: é o que o 7g mostra;
    -- nada novo é gravado fora de agenda_propostas.itens). As 2 suposições que só o bloco sabe: "juntei com Kalmar (OS-00033) no mesmo dia, na
    -- Marina Itajaí" e "evitei pôr a mesma pessoa em Balneário Camboriú e em Penha no mesmo dia (temporada)"
    if v_e ? 'suposicoes' then
      v_7d_sup := array(select x from jsonb_array_elements_text(v_e -> 'suposicoes') x);
      if v_7d_ml and coalesce((v_b ->> 'mesmo')::boolean, false) and (v_ctx -> 'loc' ->> ((v_b ->> 'i')::int - 1))::int > 0 then
        select (v_ctx -> 'oss' ->> (z.x - 1))::uuid into v_7d_os
          from (select abs((v_ctxf -> 'fr' ->> ((m.h - 1) * 4 + s.s - 1))::int) as x, m.h, s.s
                  from (select distinct 2 * d.d - k.k as h
                          from (select distinct (hh + 1) / 2 as d from unnest(public._agenda_ints(v_b -> 'h')) hh) d, generate_series(0, 1) k(k)) m,
                       generate_series(1, 4) s(s)) z
         where z.x > 0 and z.x <> (v_b ->> 'i')::int
           and (v_ctx -> 'loc' ->> (z.x - 1))::int = (v_ctx -> 'loc' ->> ((v_b ->> 'i')::int - 1))::int
         order by z.h, z.s
         limit 1;
        if found then
          v_7d_sup := v_7d_sup || format('juntei com %s no mesmo dia, %s', public._agenda_rotulo_da_os(v_7d_os),
                                         v_e ->> 'local_curto');
        end if;
      end if;
      if v_b ? 'evitou' then
        v_7d_x := (v_ctx -> 'mun' ->> ((v_b ->> 'i')::int - 1))::int;
        v_7d_sup := v_7d_sup || format('evitei pôr a mesma pessoa em %s e em %s no mesmo dia (temporada)',
                                       v_ctx -> 'mun_nomes' ->> (v_7d_x - 1), v_ctx -> 'mun_nomes' ->> ((v_b ->> 'evitou')::int - 1));
      end if;
      v_itens := jsonb_set(v_itens, '{-1}', (v_itens -> -1) || jsonb_build_object('suposicoes', to_jsonb(v_7d_sup))
                 || jsonb_strip_nulls(jsonb_build_object('local_texto', v_e ->> 'local_texto', 'viagem', v_e ->> 'viagem', 'imax_os', v_e -> 'imax_os')));
    end if;
    -- FASE 7d: fim
    -- FASE 7c: (7c P2, §5.2 3, §6.8) os motivos do compromisso, nesta ordem: o que a OS pede e quem vai (com modo_habilidade ligado e
    -- algum meio-dia do bloco pedindo: "pede quem instala sozinho com 220 V ou banco de bateria, no último dia: vai Roberto" — quem
    -- vai é quem tem o que o meio-dia pede, ou você no turno), a troca avisada do responsável ("troquei o responsável: Roberto não
    -- está livre até qua 11/11; segui com João") e o responsável que saiu da equipe ("Roberto, o responsável, não está na equipe
    -- agora"). A troca e o responsável fora só existem com modo_lider ou modo_habilidade ligado.
    v_7c_mot := '{}';
    if v_b ->> 'tipo' <> 'reserva' then
      if cf.modo_habilidade = 'ligado' and v_e ->> 'exig_texto' is not null then
        v_7c_txt := public._agenda_lista(array(
          select y.nome
            from (select case when t.p = (v_ctx ->> 'dono')::int then 'você' else v_ctx -> 'nomes' ->> (t.p - 1) end as nome, min(t.h) as h
                    from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr'),
                                public._agenda_ints(v_b -> 'ex')) t(p, h, pr, ex)
                   where t.pr = 0 and coalesce(t.ex, 0) <> 0
                     and (t.p = (v_ctx ->> 'dono')::int
                          or (t.ex & 9 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4))::int >= cf.habilidade_nivel_energizado)
                          or (t.ex & 2 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 1))::int >= cf.habilidade_nivel_comissionar)
                          or (t.ex & 8 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 1))::int >= cf.habilidade_nivel_diagnostico)
                          or (t.ex & 4 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 2))::int >= cf.habilidade_nivel_altura))
                   group by 1) y
           order by y.h, y.nome));
        if coalesce(v_7c_txt, '') <> '' then
          v_7c_mot := v_7c_mot || format('pede %s: vai %s', v_e ->> 'exig_texto', v_7c_txt);
        end if;
      end if;
      if coalesce((v_b ->> 'lt')::boolean, false) then
        -- o 1º dia, do início do bloco em diante, em que o responsável está livre de manhã ou de tarde na grade de antes do encaixe
        v_7c_lp := coalesce((v_e ->> 'lid')::int, 0);
        v_7c_d := null;
        if v_7c_lp > 0 then
          select min(g) into v_7c_d from generate_series(((v_b ->> 'ini')::int + 1) / 2, (v_ctx ->> 'nd')::int) g
           where ((v_ctx -> 'cap' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 2))::int = 1
                  and (v_ctx -> 'ocup' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 2))::int in (0, -(v_b ->> 'i')::int))
              or ((v_ctx -> 'cap' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 1))::int = 1
                  and (v_ctx -> 'ocup' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 1))::int in (0, -(v_b ->> 'i')::int));
        end if;
        v_7c_mot := v_7c_mot || format('troquei o responsável: %s não está livre %s; segui com %s', v_e ->> 'lid_nome',
                                       case when v_7c_d is null then format('nas próximas %s semanas', cf.horizonte_semanas)
                                            else 'até ' || public._dia_curto(v_ini + v_7c_d - 1) end,
                                       coalesce(nullif(public._agenda_lista(array(
                                         select y.nome from (select v_ctx -> 'nomes' ->> (t.p - 1) as nome, min(t.h) as h
                                                               from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'),
                                                                           public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
                                                              where t.pr = 0 and t.p <> (v_ctx ->> 'dono')::int group by 1) y
                                          order by y.h, y.nome)), ''), 'você'));
      end if;
      if coalesce((v_e ->> 'lid_fora')::boolean, false) then
        v_7c_mot := v_7c_mot || format('%s, o responsável, não está na equipe agora', v_e ->> 'lid_nome');
      end if;
    end if;
    if cardinality(v_7c_mot) > 0 then
      v_itens := jsonb_set(v_itens, '{-1,motivos}', coalesce(v_itens -> -1 -> 'motivos', '[]'::jsonb) || to_jsonb(v_7c_mot));
    end if;
    -- FASE 7c: fim
    -- FASE 7c: (7c correção, achado 9) a troca avisada do responsável também vai no TEXTO do item — o que vira a ação do "o que mudou",
    -- a linha "Mudei sozinho" do fechamento, o aviso do gestor e *agenda <OS>* —, não só nos motivos (que ninguém lia): "Edu (OS-97175):
    -- sex 06 e seg 09/11, você fecha, João os 2 dias, … — troquei o responsável: Roberto não está livre até qua 11/11; segui com João,
    -- Bruno e Alex." Sem caber em c_c9_max, a curta "— troquei o responsável (Roberto não está livre)". Só existe com modo_lider ou
    -- modo_habilidade ligado (o lt do bloco, que põe o motivo acima).
    v_c9_tr := (select x from unnest(v_7c_mot) x where x like 'troquei o responsável:%' limit 1);
    if v_c9_tr is not null and v_b ->> 'tipo' <> 'reserva' then
      v_c9_txt := rtrim(v_itens -> -1 ->> 'texto', '.') || ' — ' || v_c9_tr || '.';
      if char_length(v_c9_txt) > c_c9_max then
        v_c9_txt := rtrim(v_itens -> -1 ->> 'texto', '.') || format(' — troquei o responsável (%s não está livre).', v_e ->> 'lid_nome');
      end if;
      v_itens := jsonb_set(v_itens, '{-1,texto}', to_jsonb(public._agenda_corta(v_c9_txt, c_c9_max)));
    end if;
    -- FASE 7c: fim
    -- FASE 7b: (7b P4, §6.4) o item leva a dupla da OS (o texto do cartão e do foco), os meios-dias que pediam 2 e não têm a 2ª pessoa
    -- (dupla_falta [{dia, turno, onde}]) e o sábado usado; só com os modos da 7b
    if v_e ? 'dk' or v_b ? 'sabado' then
      v_itens := jsonb_set(v_itens, '{-1}', (v_itens -> -1) || jsonb_strip_nulls(jsonb_build_object(
        'dupla', v_e ->> 'dupla_texto', 'dupla_fonte', v_e ->> 'dupla_fonte',
        'dupla_falta', (select jsonb_agg(jsonb_build_object('dia', v_ini + ((f ->> 'h')::int + 1) / 2 - 1,
                                                           'turno', case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end,
                                                           'onde', f ->> 'onde') order by (f ->> 'h')::int)
                          from jsonb_array_elements(v_b -> 'dupla_falta') f),
        'sabado', case when v_b ? 'sabado' then true end)));
    end if;
    -- FASE 7b: fim
    -- CORREÇÃO FASE 6: (C1) item 14: a reserva por teto da OS que precisa do dono (abre, fecha ou o turno dele), com a
    -- capacidade do dono em uso abaixo da carga de todos (_agenda_carga_da_pessoa), diz a parte da semana DELE: "não coube na
    -- sua parte da semana (56%)", e não "na carga de 80%". Sem nada em uso, o item é o de antes, byte a byte.
    if v_b ->> 'reserva_de' = 'teto'
       and (coalesce((v_e ->> 'abre')::boolean, false) or coalesce((v_e ->> 'fecha')::boolean, false)
            or coalesce((v_e ->> 'dt_m')::boolean, false) or coalesce((v_e ->> 'dt_t')::boolean, false))
       and public._agenda_carga_da_pessoa(v_dono) < cf.carga_max then
      v_itens := jsonb_set(v_itens, '{-1,motivos}',
                   (select coalesce(jsonb_agg(case when m #>> '{}' = 'não coube na carga de ' || public._agenda_num(cf.carga_max * 100, 0) || '%'
                                                   then to_jsonb('não coube na sua parte da semana ('
                                                                 || public._agenda_num(public._agenda_carga_da_pessoa(v_dono) * 100, 0) || '%)')
                                                   else m end order by o), '[]'::jsonb)
                      from jsonb_array_elements(v_itens -> -1 -> 'motivos') with ordinality t(m, o)));
    end if;
    -- CORREÇÃO FASE 6: fim
  end loop;

  -- A condição e a data-limite das reservas condicionadas (do 1º dia de cada uma: o "compre até" daquele início).
  select coalesce(jsonb_agg(case when i ->> 'reserva_de' = 'condicionada' then
             i || x.c || jsonb_build_object('texto', rtrim(i ->> 'texto', '.') || ' — ' || (x.c ->> 'condicao') || '.')
           else i end order by k), '[]'::jsonb)
    into v_itens
    from jsonb_array_elements(v_itens) with ordinality t(i, k)
    cross join lateral (select case when i ->> 'reserva_de' = 'condicionada'
                                    then public._agenda_condicao_da_reserva((i ->> 'os')::uuid, i ->> 'condicao_tipo', (i ->> 'de')::date,
                                                                            v_info -> (i ->> 'os') -> 'pront', p_hoje) end as c) x;

  -- FASE 7c: (7c P2, §5.2 7) o "por que não cabe" lê os modos e os níveis da 7c no contexto (o que cada pessoa faz já está nele)
  v_ctx := v_ctx || jsonb_build_object('hab_modo', (cf.modo_habilidade = 'ligado')::int, 'n', v_par -> 'n',
                                       'fcobre', cf.habilidade_fechamento_cobre);
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4) o "por que não cabe" lê o pátio como o motor o deixou
  if v_rf ? 'pat_int' then
    v_ctx := v_ctx || jsonb_build_object('pat_int', v_rf -> 'pat_int');
  end if;
  -- FASE 7d: fim
  -- ── 7. O que fica de fora, com quem trava ──
  for v_e in select e from jsonb_array_elements(v_fila) e order by (e ->> 'ordem')::int loop
    v_os := (v_e ->> 'os')::uuid;
    continue when exists (select 1 from jsonb_array_elements(v_itens) i where (i ->> 'os')::uuid = v_os and i ->> 'op' = 'criar');
    v_x := (v_e ->> 'i')::int;
    v_txt := null;
    v_chave := null;
    if v_x = any (v_xnc) and exists (select 1 from jsonb_array_elements(v_perg) q where (q ->> 'x')::int = v_x) then
      select q ->> 'chave' into v_chave from jsonb_array_elements(v_perg) q where (q ->> 'x')::int = v_x;
      v_txt := format('%s: não cabe até %s — preciso de você.', public._agenda_rotulo_da_os(v_os), public._dia_curto((v_e ->> 'precisa')::date));
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', 'nao_cabe', 'texto', v_txt, 'pergunta_chave', v_chave);
      continue;
    end if;
    if v_x = any (v_sem_q) then
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                 'motivo', 'sem_encaixe',
                 'texto', format('%s: sem encaixe com a equipe de hoje (nem atrasando outra OS).', public._agenda_rotulo_da_os(v_os)));
      continue;
    end if;
    if (v_e ->> 'classe')::int = 4 then
      v_txt := format('%s: %s.', public._agenda_rotulo_da_os(v_os), rtrim(v_e ->> 'texto', '.'));
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', v_e ->> 'motivo', 'texto', v_txt);
      continue;
    end if;
    continue when coalesce((v_e ->> 'passos')::int, 0) <= 0;
    -- FASE 7b: (7b P4, R4.3(c)) a dupla dita que só saiu da espera da classe 4 por quem vem sob demanda (dupla_sd) e não achou bloco:
    -- vai ao "fora" com o motivo dupla (o da classe 4: o aviso, o foco e o cartão dizem "falta a 2ª pessoa"), com as datas de quem
    -- vem — nunca o "sem lugar" calado.
    if coalesce((v_e ->> 'dupla_sd')::boolean, false)
       and exists (select 1 from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x and f ->> 'motivo' in ('sem_encaixe', 'sem_reserva')) then
      select public._agenda_lista(array_agg(format('%s só vem %s (%s)', x.nome, public._agenda_dias_texto(x.dias),
                                                  public._agenda_plural(x.n, 'meio-dia', 'meios-dias')) order by x.nome)),
             count(*)::int
        into v_7b_x, v_7b_n
        from (select k.pessoa as nome, k.payee_id, array_agg(distinct k.dia order by k.dia) as dias, count(*)::int as n
                from public.agenda_capacidade(p_hoje, p_hoje + 7 * cf.horizonte_semanas - 1, p_hoje) k
               where not k.eh_dono and k.situacao = 'livre' and public._agenda_e_sob_demanda(k.payee_id, p_hoje)
               group by k.pessoa, k.payee_id) x;
      v_txt := format('%s: precisa de %s pessoas em %s e %s: me diga mais dias %s ou chame outro ajudante.',
                      public._agenda_rotulo_da_os(v_os), v_e ->> 'dupla_n',
                      public._agenda_plural((v_e ->> 'dupla_meios_n')::int, 'meio-dia', 'meios-dias'),
                      coalesce(nullif(v_7b_x, ''), 'quem vem sob demanda não cobre'), case when v_7b_n > 1 then 'deles' else 'dele' end);
      -- (correção da revisão da 7b, achado 22) quando os dias de quem vem sob demanda são todos antes de a OS ficar pronta, o
      -- porquê é a data, não a falta de dias ("… e Mateus só vem seg 09 e qui 12/11 (4 meios-dias), antes de o serviço ficar pronto (qua
      -- 18/11): me diga dias dele a partir de qua 18/11 ou chame outro ajudante.")
      v_7bc_est := (public.os_prontidao(v_os, p_hoje) ->> 'est')::date;
      select max(k.dia) into v_7bc_max
        from public.agenda_capacidade(p_hoje, p_hoje + 7 * cf.horizonte_semanas - 1, p_hoje) k
       where not k.eh_dono and k.situacao = 'livre' and public._agenda_e_sob_demanda(k.payee_id, p_hoje);
      if v_7bc_est is not null and v_7bc_max is not null and v_7bc_max < v_7bc_est and nullif(v_7b_x, '') is not null then
        v_txt := format('%s: precisa de %s pessoas em %s e %s, antes de o serviço ficar pronto (%s): me diga dias %s a partir de %s ou chame outro ajudante.',
                        public._agenda_rotulo_da_os(v_os), v_e ->> 'dupla_n',
                        public._agenda_plural((v_e ->> 'dupla_meios_n')::int, 'meio-dia', 'meios-dias'), v_7b_x,
                        public._dia_curto(v_7bc_est), case when v_7b_n > 1 then 'deles' else 'dele' end, public._dia_curto(v_7bc_est));
      end if;
      -- (correção da revisão da 7b: fim)
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', 'dupla', 'texto', v_txt);
      continue;
    end if;
    -- FASE 7b: fim
    select f ->> 'motivo' into v_tipo from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x limit 1;
    if v_tipo is null then
      select b into v_b from jsonb_array_elements(v_rf -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso';
      if v_b is not null and not coalesce((v_b ->> 'na_janela')::boolean, true) then
        v_tipo := 'depois';
        v_txt := format('%s: começa %s%s.', public._agenda_rotulo_da_os(v_os),
                        public._dia_curto(v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1),
                        coalesce(' (' || (select r ->> 'texto' from jsonb_array_elements(v_info -> v_os::text -> 'pront' -> 'restricoes') r
                                           where r ->> 'tipo' in ('bem', 'nao_antes') limit 1) || ')', ''));
      elsif v_x = any (v_h) then
        v_tipo := 'espera';
        v_txt := format('%s: espera a sua decisão.', public._agenda_rotulo_da_os(v_os));
      end if;
    end if;
    -- FASE 7c: (7c P2, §5.2 5, §6.8) o fora habilidade (do encaixe: não coube com quem o serviço pede, cabia sem ele): o que ela pede
    -- e que ninguém com isso fica livre junto no horizonte; no dia que o dono pediu, o "não cabe <dia>" de sempre, com o porquê do
    -- dia ("ninguém que sobe no teto fica livre nesse dia")
    if v_tipo = 'habilidade' and v_txt is null then
      v_txt := case when v_e ? 'fixar_de'
                    then format('%s: não cabe %s: %s.', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_ini + (v_e ->> 'fixar_de')::int - 1),
                                public._agenda_por_que_nao(v_ctx, v_e, (v_e ->> 'fixar_de')::int, cf.wip_max))
                    else format('%s: pede %s e ninguém com isso fica livre junto nas próximas %s semanas.', public._agenda_rotulo_da_os(v_os),
                                concat_ws(' e ', public._agenda_exigencia_texto(nullif(coalesce((v_e ->> 'ext')::int, 0), 0),
                                                                                case when coalesce((v_e ->> 'passos')::int, 0) > 1 then 'todos' end),
                                                 public._agenda_exigencia_texto(nullif(coalesce((v_e ->> 'exu')::int, 0), 0), 'ultimo')),
                                cf.horizonte_semanas) end;
    end if;
    -- FASE 7c: fim
    -- FASE 7d: (7d P4, R6.3-7, §6.2) a OS que não coube no pátio: motivo sem_encaixe (o que a linha da semana conhece) com patio_cheio e o texto próprio.
    -- Sem vagas ditas, nem nasce.
    if v_tipo = 'sem_encaixe' and v_txt is null
       and exists (select 1 from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x and coalesce((f ->> 'patio_cheio')::boolean, false)) then
      v_7d_x := (v_ctx -> 'pat' ->> (v_x - 1))::int;
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
        'motivo', 'sem_encaixe', 'patio_cheio', true,
        'texto', format('%s: %s. Me diga se cabe mais um, ou quando outro motorhome sai.', public._agenda_rotulo_da_os(v_os),
                        public._agenda_patio_frase(v_ctx -> 'pat_nomes' ->> (v_7d_x - 1), (v_ctx -> 'pat_max' ->> (v_7d_x - 1))::int, false)));
      continue;
    end if;
    -- FASE 7d: fim
    -- FASE 7d: (correção O14) a viagem com pernoite que não coube: o motivo é a janela de dias seguidos, não "a equipe de hoje". A chave viagem só existe com o modo ligado
    if v_tipo = 'sem_encaixe' and v_txt is null and v_e ->> 'viagem' = 'pernoite' then
      v_txt := format('%s: a viagem precisa de %s seguidos com a mesma equipe, e não achei essa janela em %s semanas.', public._agenda_rotulo_da_os(v_os),
                      public._agenda_plural(ceil(coalesce((v_e ->> 'passos')::numeric, 0) / 2)::int, 'dia útil', 'dias úteis'), cf.horizonte_semanas);
    end if;
    -- FASE 7d: fim
    continue when v_tipo is null;
    v_txt := coalesce(v_txt, format('%s: %s.', public._agenda_rotulo_da_os(v_os), case v_tipo
      when 'padrao_do_dono' then 'falta você dizer quais dias fica em campo'
      when 'fixar_nao_cabe' then format('não cabe %s: %s', public._dia_curto(v_ini + (v_e ->> 'fixar_de')::int - 1),
                                        public._agenda_por_que_nao(v_ctx, v_e, (v_e ->> 'fixar_de')::int, cf.wip_max))
      when 'sem_reserva' then rtrim(v_e ->> 'texto', '.') || ' (sem lugar para a reserva nesta semana)'
      when 'so_com_voce' then rtrim(v_e ->> 'texto', '.') || ' (é só com você: entra quando isso estiver respondido)'
      else format('sem encaixe em %s semanas com a equipe de hoje', cf.horizonte_semanas) end));
    v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                           'motivo', v_tipo, 'texto', v_txt);
  end loop;
  -- (as que saíram da carteira e tinham plano)
  v_fora := v_fora || coalesce((
    select jsonb_agg(jsonb_build_object('os', x.os, 'numero', v_info -> x.os::text -> 'pront' ->> 'numero',
             'cliente_curto', v_info -> x.os::text -> 'pront' ->> 'cliente_curto', 'motivo', 'fora_da_carteira',
             'texto', format('%s: %s.', public._agenda_rotulo_da_os(x.os), v_info -> x.os::text -> 'pront' ->> 'estado_texto'))
             order by v_info -> x.os::text -> 'pront' ->> 'numero')
      from (select distinct (c ->> 'os')::uuid as os from jsonb_array_elements(v_canc) c where c ->> 'motivo' = 'os_saiu') x
     where not (x.os = any (v_escopo))), '[]'::jsonb);

  -- ── 8. A carga por pessoa e semana (o publicável sem esperar) ──
  select coalesce(jsonb_object_agg(p.id, jsonb_build_object('nome', p.nome, 'semanas', p.semanas)), '{}'::jsonb) into v_carga
    from (select (v_ctx -> 'pessoas' ->> (pp - 1)) as id, (v_ctx -> 'nomes' ->> (pp - 1)) as nome,
                 jsonb_agg(jsonb_build_object(
                   'semana', v_seg + 7 * (ww - 1),
                   'esperado', (v_ctxf -> 'esperado' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'teto80', (v_ctxf -> 'teto80' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'teto100', (v_ctxf -> 'teto100' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'compromisso', (v_ctxf -> 'uso_c' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'reserva', (v_ctxf -> 'uso_r' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1))) order by ww) as semanas
            from generate_series(1, (v_ctx ->> 'np')::int) pp
            cross join generate_series((v_de - v_seg) / 7 + 1, (v_ate - v_seg) / 7 + 1) ww
           group by pp) p;

  -- ── 9. A pontuação (para comparar alternativas) ──
  select jsonb_build_object(
           'atraso_dias', coalesce(sum(greatest((i ->> 'fim_depois')::date - (v_ent -> x.ii ->> 'precisa')::date, 0))
                                     filter (where v_ent -> x.ii ->> 'precisa' is not null), 0),
           'mudancas', (select count(*) from jsonb_array_elements(v_canc) c where not (c ->> 'violada')::boolean and c ->> 'motivo' = 'replanejado'),
           'meios_do_dono', coalesce(sum((i ->> 'meios_do_dono')::int), 0),
           'interrupcoes', coalesce(sum((i ->> 'interrupcoes')::int), 0),
           'fim', coalesce(sum((i ->> 'ate')::date - v_ini), 0))
    into v_pont
    from jsonb_array_elements(v_itens) i
    cross join lateral (select (select e ->> 'i' from jsonb_array_elements(v_fila) e where e ->> 'os' = i ->> 'os') as ii) x
   where i ->> 'op' = 'criar' and not coalesce((i ->> 'espera')::boolean, false);
  v_pont := v_pont || jsonb_build_object('total',
    (v_pont ->> 'atraso_dias')::bigint * c_peso_atraso + (v_pont ->> 'mudancas')::bigint * c_peso_mudanca
    + (v_pont ->> 'meios_do_dono')::bigint * c_peso_dono + (v_pont ->> 'interrupcoes')::bigint * c_peso_interr
    + (v_pont ->> 'fim')::bigint * c_peso_fim);

  -- ── 10. Os textos prontos ──
  v_feriados := array(select format('%s é %s', public._agenda_dia_sem_mes(g::date), public.agenda_feriado(g::date))
                        from generate_series(v_de - (extract(isodow from v_de)::int - 1), v_ate, interval '1 day') g
                       where extract(isodow from g)::int <= 5 and public.agenda_feriado(g::date) is not null order by g);
  v_titulo := case when p_escopo = 'semana'
    then format('Semana de %s a %s', to_char(v_de, 'DD'),
                to_char(coalesce((select max(g::date) from generate_series(v_de, v_ate, interval '1 day') g
                                   where public.agenda_dia_util(g::date)), v_ate), 'DD/MM'))
         || coalesce(' (' || nullif(array_to_string(v_feriados, ', '), '') || ')', '')
    else 'Mudanças na agenda' end;
  v_linhas := array(select i ->> 'texto' || case when coalesce((i ->> 'espera')::boolean, false) then ' (espera a sua decisão)' else '' end
                      from jsonb_array_elements(v_itens) with ordinality t(i, k)
                     order by i ->> 'op' = 'cancelar', (i ->> 'de')::date, i ->> 'numero' collate "C", k);
  v_tfora := array(select f ->> 'texto' from jsonb_array_elements(v_fora) with ordinality t(f, k) order by k);
  v_textos := jsonb_build_object('titulo', v_titulo, 'linhas', to_jsonb(v_linhas), 'fora', to_jsonb(v_tfora),
    'carga', to_jsonb(array(
      select format('%s: %s de %s meios-dias de serviço na semana de %s',
                    case when p.key::uuid is not distinct from v_dono then 'Você' else p.value ->> 'nome' end,
                    s ->> 'compromisso', s ->> 'teto80', to_char((s ->> 'semana')::date, 'DD/MM'))
        from jsonb_each(v_carga) p, jsonb_array_elements(p.value -> 'semanas') s
       where (s ->> 'esperado')::numeric > 0
       order by (s ->> 'semana')::date, p.key::uuid is not distinct from v_dono desc, p.value ->> 'nome')),
    'resumo', format('%s: %s, %s.', v_titulo,
                     public._agenda_plural((select count(distinct i ->> 'os')::int from jsonb_array_elements(v_itens) i
                                             where i ->> 'op' = 'criar' and not (i ->> 'espera')::boolean), 'serviço marcado', 'serviços marcados'),
                     public._agenda_plural(jsonb_array_length(v_fora), 'de fora', 'de fora')));
  -- CORREÇÃO 29/10 (P3): o marcado firme e o reservado separados no resumo e no título da semana (com a agenda automática
  -- ligada). A reserva só guarda o lugar da equipe (nada está marcado até a condição dela se cumprir), e o resumo de antes
  -- contava como "serviço marcado" toda OS que entra: com só a reserva do Lenine, "1 serviço marcado". Com reserva no que
  -- entra (sem o que espera a decisão), o resumo diz quem: "1 reservado (Lenine), nada marcado firme, 10 de fora"; e o título
  -- da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme"): é ele que abre o
  -- "Publiquei a semana de …" da aplicação, do que mudou e do fechamento, que listam as OS logo depois. A OS com algum
  -- meio-dia firme conta como marcada. No resumo, o nome curto do cliente, com o número quando o nome se repete ("Kalmar
  -- OS-00032"); até 3 nomes, depois "e mais N". Sem reserva, ou fora de ligado, os dois são os de antes, byte a byte.
  if v_modo = 'ligado' then
    select coalesce(array_agg(x.nome order by x.de, x.numero collate "C") filter (where x.firme), '{}'::text[]),
           coalesce(array_agg(x.nome order by x.de, x.numero collate "C") filter (where not x.firme), '{}'::text[])
      into v_marc, v_resv
      from (select y.numero, y.de, y.firme,
                   case when count(*) over (partition by y.curto) > 1 then concat_ws(' ', y.curto, y.numero) else y.curto end as nome
              from (select min(i ->> 'numero') as numero, min((i ->> 'de')::date) as de, bool_or(i ->> 'tipo' <> 'reserva') as firme,
                           coalesce(public._agenda_nome_curto(min(i ->> 'cliente_curto')), min(i ->> 'numero')) as curto
                      from jsonb_array_elements(v_itens) i
                     where i ->> 'op' = 'criar' and not coalesce((i ->> 'espera')::boolean, false)
                     group by i ->> 'os') y) x;
  end if;
  if cardinality(v_resv) > 0 then
    v_contagem := case when cardinality(v_marc) > 0
                       then format('%s (%s), %s (%s)',
                                   public._agenda_plural(cardinality(v_marc), 'serviço marcado', 'serviços marcados'),
                                   public._agenda_lista(v_marc, 3),
                                   public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'), public._agenda_lista(v_resv, 3))
                       else format('%s (%s), nada marcado firme',
                                   public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'), public._agenda_lista(v_resv, 3))
                  end;
    v_textos := v_textos || jsonb_build_object('resumo', format('%s: %s, %s.', v_titulo, v_contagem,
                                                               public._agenda_plural(jsonb_array_length(v_fora), 'de fora', 'de fora')));
    if p_escopo = 'semana' then
      v_titulo := v_titulo || ' — '
                  || case when cardinality(v_marc) > 0
                          then format('%s, %s', public._agenda_plural(cardinality(v_marc), 'serviço marcado', 'serviços marcados'),
                                      public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'))
                          else format('%s, nada marcado firme', public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'))
                     end;
      v_textos := v_textos || jsonb_build_object('titulo', v_titulo);
    end if;
  end if;
  -- CORREÇÃO 29/10 (P3): fim
  v_texto := v_titulo
    || coalesce(E'\n' || nullif(array_to_string(array(select '• ' || x from unnest(v_linhas) x), E'\n'), ''), E'\nNada a mudar.')
    || coalesce(E'\nFora: ' || nullif(array_to_string(v_tfora, '; '), ''), '')
    || case when p_persistir then '' else E'\nÉ simulação: não muda nada.' end;

  -- FASE 7b: (7b P4, §6.3, R4.3(a)4) em teste, o que a 7b faria e não fez — o sábado ("Em teste: para cumprir o prazo de Vanderlei
  -- (qua 18/11), eu usaria sáb 14/11 de manhã com Rafael, que se ofereceu.") e a dupla de 1 pessoa ("Em teste: no Lenine eu pediria
  -- um ajudante em qua 04/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas."): textos.em_teste e no fim do texto.
  for v_7b_b in select e from jsonb_array_elements(coalesce(v_rf -> 'sab_teste', '[]'::jsonb)) e loop
    v_7b_e := v_ent -> (v_7b_b ->> 'i');
    select array_agg(distinct (a ->> 'dia')::date order by (a ->> 'dia')::date) into v_7b_dias
      from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_7b_b -> 'b')) a
     where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno';
    v_7b_nomes := array(select y.x from (select a ->> 'nome' as x, min(o) as o
                                           from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_7b_b -> 'b')) with ordinality t(a, o)
                                          where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' group by 1) y
                         order by y.o);
    v_7b_teste := v_7b_teste || case when v_7b_e ? 'prazo'
      then format('Em teste: para cumprir o prazo de %s (%s), eu usaria %s de manhã com %s, que %s.',
                  public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'), public._dia_curto((v_7b_e ->> 'prazo')::date),
                  public._agenda_dias_texto(v_7b_dias), public._agenda_lista(v_7b_nomes),
                  case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end)
      else format('Em teste: %s terminaria antes com %s de manhã (%s %s).', public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'),
                  public._agenda_dias_texto(v_7b_dias), public._agenda_lista(v_7b_nomes),
                  case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end) end;
  end loop;
  if cf.modo_dupla = 'sombra' then
    for v_7b_b in select b from jsonb_array_elements(v_rf -> 'colocadas') b
                   where b ? 'dupla_falta' and jsonb_array_length(b -> 'dupla_falta') > 0 and coalesce((b ->> 'na_janela')::boolean, true)
                     and not ((b ->> 'i')::int = any (v_xnc) and b ->> 'tipo' = 'compromisso') loop
      v_7b_e := v_ent -> (v_7b_b ->> 'i');
      v_7b_teste := v_7b_teste || format('Em teste: no %s eu pediria um ajudante em %s: %s pede 2 pessoas.',
        public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'),
        public._agenda_lista(array(
          select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ' (manhã e tarde)'
                                                when bool_or(z.t = 'manha') then ' (manhã)' else ' (tarde)' end
            from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                    from jsonb_array_elements(v_7b_b -> 'dupla_falta') f) z
           group by z.d order by z.d)),
        coalesce(case when coalesce((v_7b_e ->> 'dupla_todos')::boolean, false) then v_7b_e ->> 'dupla_rot_todos' end,
                 nullif(public._agenda_lista(array_remove(array[nullif(v_7b_e ->> 'dupla_rot_ini', ''), nullif(v_7b_e ->> 'dupla_rot_fim', '')], null)), ''),
                 'a tarefa'));
    end loop;
  end if;
  if cardinality(v_7b_teste) > 0 then
    v_textos := v_textos || jsonb_build_object('em_teste', to_jsonb(v_7b_teste));
    v_texto := v_texto || E'\n' || array_to_string(v_7b_teste, E'\n');
  end if;
  -- FASE 7b: fim
  -- ── 11. A validação: proposta inválida nunca sai ──
  v_viol := public._agenda_validar_itens(v_itens, jsonb_build_object('p_restricoes', v_r), p_hoje, p_agora, false,
              (select jsonb_object_agg(k, x -> 'pront') from jsonb_each(v_info) t(k, x)));
  if jsonb_array_length(v_viol) > 0 then
    raise exception 'agenda_propor: a proposta saiu inválida (erro do motor): %', v_viol::text
      using errcode = 'P0001', detail = left(v_texto, 2000);
  end if;

  -- ── 12. Persistir ──
  if p_persistir then
    -- a aberta anterior do mesmo escopo e modo (e das mesmas OS, fora da semana) fica obsoleta; as alocações dela saem
    for v_q in
      select to_jsonb(pr) from public.agenda_propostas pr
       where pr.estado = 'aberta' and pr.escopo = p_escopo and pr.modo = v_modo
         and (p_escopo = 'semana' or pr.os_alvo && v_escopo)
       order by pr.criada_em, pr.id
    loop
      update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'refeita' where id = (v_q ->> 'id')::uuid;
      delete from public.agenda_alocacoes where proposta_id = (v_q ->> 'id')::uuid and estado = 'proposta';
    end loop;
    v_pid := gen_random_uuid();
    -- os ids das alocações novas entram no item (é por eles que o aplicar publica)
    select coalesce(jsonb_agg(case when i ->> 'op' = 'criar'
             then i || jsonb_build_object('alocacoes', (select jsonb_agg(a || jsonb_build_object('alocacao_id', gen_random_uuid()) order by j)
                                                          from jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)))
             else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
    v_expira := least(p_agora + cf.proposta_validade,
                      coalesce((select min(lower(public.agenda_periodo((a ->> 'dia')::date, a ->> 'turno', a ->> 'presenca')))
                                  from jsonb_array_elements(v_itens) i, jsonb_array_elements(i -> 'alocacoes') a
                                 where i ->> 'op' = 'criar'), p_agora + cf.proposta_validade));
    insert into public.agenda_propostas (id, escopo, periodo, os_alvo, versao_base, modo, estado, itens, fora, carga, textos,
                                         parametros, pontuacao, criada_por, autor, criada_em, expira_em)
    values (v_pid, p_escopo, daterange(v_de, v_ate, '[]'), v_escopo, v0, v_modo, 'aberta', v_itens, v_fora, v_carga, v_textos,
            jsonb_build_object('p_hoje', p_hoje, 'p_agora', p_agora, 'p_de', p_de, 'p_ate', p_ate, 'p_os', to_jsonb(p_os),
                               'p_restricoes', v_r, 'escopo', p_escopo, 'origem', p_origem, 'de', v_de, 'ate', v_ate),
            v_pont, p_origem, p_autor, p_agora, v_expira);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id,
                                         reserva_de, condicao, condicao_tipo, condicao_ate, motivos, criado_em)
    select (a ->> 'alocacao_id')::uuid, (i ->> 'os')::uuid, (a ->> 'payee_id')::uuid, (a ->> 'dia')::date, a ->> 'turno',
           a ->> 'presenca', i ->> 'tipo', 'proposta', case when (i ->> 'fixar_dono')::boolean then 'dono' else 'motor' end, v_pid,
           i ->> 'reserva_de', case when a ->> 'presenca' = 'turno' then i ->> 'condicao' end,
           case when a ->> 'presenca' = 'turno' then i ->> 'condicao_tipo' end,
           case when a ->> 'presenca' = 'turno' then (i ->> 'condicao_ate')::date end,
           coalesce(i -> 'motivos', '[]'::jsonb), p_agora
      from jsonb_array_elements(v_itens) with ordinality t(i, k), jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)
     where i ->> 'op' = 'criar'
     order by k, j;
    -- as perguntas críticas (a mesma pergunta não abre duas vezes; a de uma versão anterior da mesma OS sai)
    for v_q in select q from jsonb_array_elements(v_perg) q loop
      update public.agenda_perguntas p
         set estado = 'descartada', resolvida_motivo = 'a agenda mudou: a pergunta foi refeita'
       where p.estado = 'aberta' and p.modo = v_modo and p.tipo = v_q ->> 'tipo'
         and p.service_order_id = (v_q ->> 'service_order_id')::uuid and p.chave <> v_q ->> 'chave';
      insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao,
                                           recomendacao_texto, proposta_id, versao_base, modo, criada_em)
      values (v_q ->> 'tipo', v_q ->> 'chave', (v_q ->> 'service_order_id')::uuid,
              array(select x::uuid from jsonb_array_elements_text(v_q -> 'os_ids') x), null, (v_q ->> 'perda_em')::date,
              v_q ->> 'texto', v_q -> 'opcoes', (v_q ->> 'recomendacao')::smallint, v_q ->> 'recomendacao_texto', v_pid, v0, v_modo, p_agora)
      on conflict (chave, modo) where estado = 'aberta' do nothing;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true, 'proposta_id', v_pid, 'versao_base', v0, 'escopo', p_escopo, 'modo', v_modo,
    'periodo', jsonb_build_object('de', v_de, 'ate', v_ate), 'simulacao', not p_persistir,
    'itens', v_itens, 'fora', v_fora, 'carga', v_carga,
    'perguntas', (select coalesce(jsonb_agg(q - 'x' order by q ->> 'chave'), '[]'::jsonb) from jsonb_array_elements(v_perg) q),
    'pontuacao', v_pont, 'textos', v_textos, 'texto', v_texto);
end;
$function$;

create or replace function public._agenda_gestor_onda_conta(p_itens jsonb)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_crit  uuid[] := array(select distinct (i ->> 'os')::uuid from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) i
                           where i ->> 'critica' is not null);
  v_sel   jsonb := (select coalesce(jsonb_agg(i order by k), '[]'::jsonb)
                      from jsonb_array_elements(public._agenda_itens_escolhidos(coalesce(p_itens, '[]'::jsonb), null, null))
                           with ordinality t(i, k)
                     where not ((i ->> 'os')::uuid = any (v_crit)));
  v_os    uuid[];
  v_dias  jsonb;
  v_nomes text[];
  v_mot   text;
  v_quem  text[];
  v_ev    uuid[];
  v_perda date;
begin
  with
  canc as (
    select (i ->> 'os')::uuid as os, x ->> 'payee_id' as payee, x ->> 'dia' as dia, x ->> 'turno' as turno,
           coalesce(x ->> 'presenca', 'turno') as presenca
      from jsonb_array_elements(v_sel) i, jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) x
     where i ->> 'op' = 'cancelar' and coalesce(i ->> 'tipo', '') <> 'reserva' and coalesce(i ->> 'motivo', '') <> 'promovida'),
  cria as (
    select (i ->> 'os')::uuid as os, x ->> 'payee_id' as payee, x ->> 'dia' as dia, x ->> 'turno' as turno,
           coalesce(x ->> 'presenca', 'turno') as presenca
      from jsonb_array_elements(v_sel) i, jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) x
     where i ->> 'op' = 'criar' and coalesce(i ->> 'tipo', '') <> 'reserva'),
  saiu as (
    select c.*, public._agenda_dia_avisado(c.payee::uuid, c.os, c.dia::date) as avisado
      from canc c
     where not exists (select 1 from cria n where n.os = c.os and n.payee = c.payee and n.dia = c.dia and n.turno = c.turno
                                              and n.presenca = c.presenca))
  select array(select distinct c.os from canc c
                where exists (select 1 from cria n where n.os = c.os)
                  and not exists (select 1 from cria n where n.os = c.os and n.dia = c.dia and n.turno = c.turno)
                order by 1),
         (select coalesce(jsonb_agg(jsonb_build_object('dia', d.dia, 'quem', d.quem) order by d.dia), '[]'::jsonb)
            from (select s.dia, case when bool_or(s.avisado = 'cliente') then 'cliente' else 'equipe' end as quem
                    from saiu s where s.avisado is not null group by s.dia) d),
         (select min(x.dia::date) from (select dia from canc union all select dia from cria) x)
    into v_os, v_dias, v_perda;

  v_nomes := array(select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                     from unnest(v_os) o join public.service_orders so on so.id = o
                     left join public.clients cl on cl.id = so.client_id
                    order by 1);
  -- o porquê: a violação com mais meios-dias entre as OS que mudam (sem elas, entre tudo o que sai); no empate, quem não vem
  select g.motivo, g.quem into v_mot, v_quem
    from (select i ->> 'motivo' as motivo, count(*) as n,
                 array_agg(distinct x ->> 'nome') filter (where x ->> 'nome' is not null) as quem
            from jsonb_array_elements(v_sel) i, jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) x
           where i ->> 'op' = 'cancelar' and coalesce((i ->> 'violada')::boolean, false)
             and (cardinality(v_os) = 0 or (i ->> 'os')::uuid = any (v_os))
           group by i ->> 'motivo') g
   order by g.n desc, g.motivo = 'pessoa' desc, g.motivo
   limit 1;
  v_ev := array(select distinct (i ->> 'os')::uuid from jsonb_array_elements(v_sel) i
                 where i ->> 'op' = 'criar' and coalesce((i ->> 'evento_real')::boolean, false) order by 1);
  return jsonb_build_object(
    'os', to_jsonb(v_os), 'os_n', coalesce(cardinality(v_os), 0), 'nomes', to_jsonb(v_nomes),
    'dias', v_dias, 'dias_n', jsonb_array_length(v_dias),
    'equipe_n', (select count(*) from jsonb_array_elements(v_dias) d where d ->> 'quem' = 'equipe'),
    'cliente_n', (select count(*) from jsonb_array_elements(v_dias) d where d ->> 'quem' = 'cliente'),
    'motivo', case v_mot
                when 'pessoa' then case when coalesce(cardinality(v_quem), 0) = 0 then 'faltou gente'
                                        when cardinality(v_quem) = 1 then v_quem[1] || ' não vem'
                                        else public._agenda_lista(v_quem, 3) || ' não vêm' end
                when 'material' then 'o material atrasou'
                when 'cliente' then 'o cliente ou o bem não está liberado'
                when 'os_saiu' then 'serviço saiu da carteira'
                when 'espera' then 'você pôs serviço em espera'
                -- FASE 7d: (correção C1) o passo calendario: a pergunta da onda diz o motivo
                when 'local' then 'o local não recebe a equipe nesses dias'
                -- FASE 7d: fim
                when 'clima' then 'choveu'
              end,
    'evento_real', to_jsonb(v_ev), 'perda_em', v_perda);
end;
$function$;

create or replace function public._agenda_combinar_da_os(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_dono   uuid := public._agenda_dono(null);
  v_dias   date[];
  v_meios  int;
  v_d1     date;
  v_dn     date;
  v_l      jsonb;
  v_tipo   text;
  v_bem    jsonb;
  v_sit    text;
  v_o_bem  text;
  v_cli    text;
  v_au     jsonb;
  v_aut    uuid[];
  v_exige  boolean;
  v_falta  uuid[];
  v_nomes  text[];
  v_ok     boolean;
  v_ate    date;
  v_base   jsonb;
  v_i      jsonb;
  v_out    jsonb := '[]'::jsonb;
  pl       public.os_planejamento;
begin
  if p_os is null or p_hoje is null then
    raise exception '_agenda_combinar_da_os: faltam a OS ou o dia' using errcode = '22004';
  end if;
  -- FASE 7d: (correção O4) serviço começado não é cobrado do que vem antes dele: o mesmo sinal plano_comecou da guarda do M11 (_agenda_cliente_onde_fica). Acesso, vaga, descida e
  -- entrada são preparo: quem já foi não prepara. Saem daqui o foco "Em teste, eu cobraria", a ação em teste, a pergunta, a crítica e a frase da ficha: todos leem esta função.
  if (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = p_os and a.estado in ('publicada', 'fixada')) <= p_hoje then
    return v_out;
  end if;
  -- FASE 7d: fim
  -- O plano vigente, sem reserva, de hoje em diante
  select coalesce(array_agg(distinct a.dia order by a.dia), '{}'::date[]), count(distinct (a.dia, a.turno)) filter (where a.presenca = 'turno')::int
    into v_dias, v_meios
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje;
  if cardinality(v_dias) = 0 then
    return v_out;
  end if;
  v_d1 := v_dias[1];
  v_dn := v_dias[cardinality(v_dias)];
  v_l := public._agenda_local_resolvido(p_os, p_hoje);
  v_tipo := v_l ->> 'tipo';
  v_bem := public._agenda_estado_do_bem(p_os, p_hoje);
  v_sit := v_bem ->> 'situacao';
  v_o_bem := case v_bem ->> 'classe' when 'rv' then 'motorhome' when 'barco' then 'barco' else 'bem' end;
  select * into pl from public.os_planejamento x where x.service_order_id = p_os;
  select public._agenda_nome_curto(cl.name) into v_cli
    from public.service_orders so join public.clients cl on cl.id = so.client_id where so.id = p_os;
  v_base := jsonb_build_object('fim', v_dn, 'cliente', v_cli, 'bem', v_o_bem, 'local', v_l ->> 'nome', 'local_id', case when coalesce((v_l ->> 'suposicao')::boolean, false) then null else v_l ->> 'local_id' end,
                               'nominal', false, 'pessoas', '[]'::jsonb, 'nomes', '[]'::jsonb, 'nota', null);

  -- [R] o acesso, em local de terceiro: o combinado é o acesso_ok_em dentro da validade (a régua da Fase 5) OU, no local que exige autorização
  -- com o nome, todas as pessoas alocadas (sem o dono) em os_autorizados. O pátio da HBR não é de terceiro.
  if v_tipo in ('marina', 'estaleiro', 'patio_parceiro', 'casa_cliente', 'outro') then
    v_au := public._agenda_autorizacao_da_os(p_os, p_hoje, v_l);
    v_aut := array(select x::uuid from jsonb_array_elements_text(coalesce(v_au -> 'autorizados', '[]'::jsonb)) x);
    v_exige := coalesce((v_au ->> 'exige')::boolean, false);
    select coalesce(array_agg(x.payee_id order by x.nome, x.payee_id), '{}'::uuid[]), coalesce(array_agg(x.nome order by x.nome, x.payee_id), '{}'::text[])
      into v_falta, v_nomes
      from (select distinct a.payee_id, public._agenda_nome_curto(py.name) as nome
              from public.agenda_alocacoes a
              join public.payees py on py.id = a.payee_id
             where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
               and a.payee_id is distinct from v_dono and not (a.payee_id = any (v_aut))) x;
    v_ok := (pl.acesso_ok_em at time zone 'America/Sao_Paulo')::date > p_hoje - c.cliente_acesso_validade_dias;
    v_ok := coalesce(v_ok, false) or (v_exige and cardinality(v_falta) = 0);
    v_ate := public.agenda_somar_du(v_d1, -c.autorizacao_antecedencia_du);
    v_i := v_base || jsonb_build_object('tipo', 'acesso', 'para', v_d1, 'ate', v_ate, 'quem', 'cliente', 'pessoas', to_jsonb(v_falta),
                                        'nomes', to_jsonb(v_nomes), 'combinado', v_ok, 'vencido', not v_ok and v_ate <= p_hoje,
                                        'nota', v_au -> 'nota', 'nominal', v_exige and coalesce((v_au ->> 'conferido')::boolean, false),
                                        'modo', public._agenda_local_modo('acesso'));
    v_out := v_out || jsonb_build_array(v_i || jsonb_build_object('texto', public._agenda_combinar_texto(v_i, 'foco', p_hoje)));
  end if;

  -- A vaga de serviço na garagem seca
  if v_sit = 'garagem_seca' and v_meios >= c.garagem_reserva_min_meios then
    v_ok := pl.reserva_marina_ok_em is not null;
    v_ate := public.agenda_somar_du(v_d1, -c.marina_reserva_antecedencia_du);
    v_i := v_base || jsonb_build_object('tipo', 'reserva_marina', 'para', v_d1, 'ate', v_ate, 'quem', 'marina', 'combinado', v_ok,
                                        'vencido', not v_ok and v_ate <= p_hoje, 'modo', public._agenda_local_modo('bem'));   -- (correção O10) <=, como o acesso
    v_out := v_out || jsonb_build_array(v_i || jsonb_build_object('texto', public._agenda_combinar_texto(v_i, 'foco', p_hoje)));
  end if;

  -- A descida para o teste na água: o último dia. A spec não dá antecedência: é a da marina, a mesma régua da vaga (notas do P5, desvio 3).
  if v_bem ->> 'exige' = 'agua' and v_sit in ('seco', 'garagem_seca') then
    v_ok := pl.descida_ok_em is not null;
    v_ate := public.agenda_somar_du(v_dn, -c.marina_reserva_antecedencia_du);
    v_i := v_base || jsonb_build_object('tipo', 'descida', 'para', v_dn, 'ate', v_ate, 'quem', coalesce(v_bem ->> 'descer_quem', 'o cliente ou a marina'),
                                        'combinado', v_ok, 'vencido', not v_ok and v_ate <= p_hoje, 'modo', public._agenda_local_modo('bem'));   -- (correção O10)
    v_out := v_out || jsonb_build_array(v_i || jsonb_build_object('texto', public._agenda_combinar_texto(v_i, 'foco', p_hoje)));
  end if;

  -- A entrada do bem no pátio
  if v_tipo in ('patio_hbr', 'patio_parceiro') then
    v_ok := pl.entrada_em is not null and pl.entrada_em <= v_d1;
    v_ate := public.agenda_somar_du(v_d1, -c.patio_entrada_antecedencia_du);
    v_i := v_base || jsonb_build_object('tipo', 'entrada', 'para', v_d1, 'ate', v_ate, 'quem', 'cliente', 'combinado', v_ok,
                                        'vencido', not v_ok and v_ate <= p_hoje, 'modo', public._agenda_local_modo('patio'));   -- (correção O10)
    v_out := v_out || jsonb_build_array(v_i || jsonb_build_object('texto', public._agenda_combinar_texto(v_i, 'foco', p_hoje)));
  end if;
  return v_out;
end;
$function$;

create or replace function public._agenda_local_resolver(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  q      record;
  v_tipo text;
  v_i    jsonb;
  v_mot  text;
  v_res  int := 0;
  v_desc int := 0;
begin
  for q in select x.id, x.tipo, x.chave, x.service_order_id, x.perda_em from public.agenda_perguntas x
            where x.estado = 'aberta' and x.tipo in ('combinar', 'acesso') order by x.criada_em, x.id loop
    -- O modo CRU: com *gestor, só propor* a pergunta segue de pé (R6.7b). O modo voltou a teste ou foi desligado: ela não pode mais ser respondida
    if coalesce(public._agenda_modo_da_pergunta(q.tipo, q.chave), 'desligado') <> 'ligado' then
      update public.agenda_perguntas set estado = 'descartada', resolvida_motivo = 'o modo voltou a teste: a pergunta não vale mais'
       where id = q.id;
      v_desc := v_desc + 1;
      continue;
    end if;
    v_tipo := case when q.tipo = 'acesso' then 'acesso' else split_part(q.chave, ':', 2) end;
    v_mot := null;
    v_i := null;
    -- A crítica diz "amanhã": no dia, ela já não tem o que perguntar
    if q.perda_em < p_hoje or (q.tipo = 'acesso' and q.perda_em = p_hoje) then
      v_mot := 'o dia passou';
    else
      select e into v_i from jsonb_array_elements(public._agenda_combinar_da_os(q.service_order_id, p_hoje)) e where e ->> 'tipo' = v_tipo;
      if v_i is null or (v_i ->> 'para')::date is distinct from q.perda_em then
        -- (correção O4) o serviço que começou não tem mais o que combinar: não é plano que mudou
        v_mot := case when (select min(a.dia) from public.agenda_alocacoes a
                             where a.service_order_id = q.service_order_id and a.estado in ('publicada', 'fixada')) <= p_hoje
                      then 'o serviço já começou' else 'o plano mudou' end;
      elsif (v_i ->> 'combinado')::boolean then
        v_mot := case when v_tipo = 'acesso' and (v_i ->> 'nominal')::boolean and jsonb_array_length(v_i -> 'pessoas') = 0 then 'a autorização foi anotada'
                      when v_tipo = 'acesso' then 'o acesso foi anotado'
                      else 'já foi combinado' end;
      end if;
    end if;
    if v_mot is not null then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = v_mot where id = q.id;
      v_res := v_res + 1;
    end if;
  end loop;
  return jsonb_build_object('resolvidas', v_res, 'descartadas', v_desc);
end;
$function$;

create or replace function public._agenda_local_combinar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c_janela constant int := 21;   -- estrutural: o plano das próximas 3 semanas (§5.5)
  cf      public.agenda_config := public._agenda_cfg();
  r       record;
  e       jsonb;
  v_para  date;
  v_crit  boolean;
  v_chave text;
  v_r     jsonb;
  v_ab    int := 0;
  v_cr    int := 0;
  v_tes   int := 0;
  v_vd    int := 0;
  v_n     int;
  v_opc   jsonb;
  -- FASE 7d: (correção R6) a OS que falha não derruba as outras
  v_err   int := 0;
  v_estado text;
  v_msg   text;
  -- FASE 7d: fim
begin
  v_r := public._agenda_local_resolver(p_hoje, p_agora);
  for r in
    select distinct a.service_order_id as os
      from public.agenda_alocacoes a
      join public.os_carteira(p_hoje) k on k.service_order_id = a.service_order_id
     where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia between p_hoje and p_hoje + c_janela
     order by 1
  loop
    -- FASE 7d: (correção R6) cada OS na sua subtransação: uma que lança não apaga as outras, e a rodada conta o erro
    begin
    -- FASE 7d: fim
    for e in select x from jsonb_array_elements(public._agenda_combinar_da_os(r.os, p_hoje)) x loop
      continue when (e ->> 'combinado')::boolean or e ->> 'modo' = 'desligado';
      v_para := (e ->> 'para')::date;
      -- No dia, não há mais o que combinar: a ficha da véspera já avisou
      continue when v_para <= p_hoje;
      v_crit := e ->> 'tipo' = 'acesso' and p_hoje >= public.agenda_somar_du(v_para, -cf.acesso_urgente_du);
      continue when not (e ->> 'vencido')::boolean;
      v_chave := format('combinar:%s:%s:%s', e ->> 'tipo', r.os, v_para);

      -- Em teste (também com o freio: nenhuma pergunta nova): só a ação, uma vez por chave, e sem entrar no fechamento (contada): as linhas ficam
      -- byte a byte. O "o que mudou" a mostra.
      if e ->> 'modo' = 'sombra' then
        if not exists (select 1 from public.agenda_acoes a
                        where a.tipo = 'local' and not a.executada and a.service_order_id = r.os and a.depois ->> 'chave' = v_chave) then
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, depois, texto, contada_em)
          values (clock_timestamp(), p_hoje, false, 'vigia', 'local', r.os, array[r.os], jsonb_build_object('chave', v_chave),
                  public._agenda_corta(public._agenda_combinar_texto(e, 'em_teste', p_hoje), 400), p_agora);
          v_tes := v_tes + 1;
        end if;
        continue;
      end if;

      v_opc := jsonb_build_object('n', 1, 'efeito', jsonb_build_object('local', 'combinado', 'item', e - 'texto'));
      if v_crit then
        -- D-1: a combinar fecha e nasce a crítica, na mesma rodada: o dono nunca recebe as duas (R6.7c-2)
        update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'virou decisão'
         where chave = v_chave and modo = 'ligado' and estado = 'aberta';
        v_chave := format('acesso:%s:%s', r.os, v_para);
        insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao, versao_base, modo,
                                             criada_em, expira_em)
        values ('acesso', v_chave, r.os, array[r.os], v_para, v_para, left(public._agenda_corta(public._agenda_combinar_texto(e, 'urgente', p_hoje), 600), 600),
                jsonb_build_array(v_opc || jsonb_build_object('texto', 'Está combinado'),
                                  jsonb_build_object('n', 2, 'texto', 'Vou combinar hoje', 'efeito', jsonb_build_object('local', 'nada')),
                                  jsonb_build_object('n', 3, 'texto', 'Segure o dia', 'efeito', jsonb_build_object('local', 'segurar'))),
                2, cf.versao_plano, 'ligado', p_agora, ((v_para + 1)::timestamp at time zone 'America/Sao_Paulo'))
        on conflict (chave, modo) where estado = 'aberta' do nothing;
        get diagnostics v_n = row_count;
        v_cr := v_cr + v_n;
      else
        -- "Amanhã eu pergunto de novo": a que o dono respondeu hoje volta só na rodada de amanhã
        continue when exists (select 1 from public.agenda_perguntas q
                               where q.chave = v_chave and q.modo = 'ligado'
                                 and (q.respondida_em at time zone 'America/Sao_Paulo')::date = p_hoje);
        insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, modo, criada_em, expira_em)
        values ('combinar', v_chave, r.os, array[r.os], v_para, v_para, left(public._agenda_corta(public._agenda_combinar_texto(e, 'pergunta', p_hoje), 600), 600),
                jsonb_build_array(v_opc || jsonb_build_object('texto', case e ->> 'tipo' when 'acesso' then 'Já está' when 'entrada' then 'Já combinou'
                                                                                         else 'Já combinei' end),
                                  jsonb_build_object('n', 2, 'texto', 'Ainda não', 'efeito', jsonb_build_object('local', 'nada'))),
                'ligado', p_agora, ((v_para + 1)::timestamp at time zone 'America/Sao_Paulo'))
        on conflict (chave, modo) where estado = 'aberta' do nothing;
        get diagnostics v_n = row_count;
        v_ab := v_ab + v_n;
      end if;
    end loop;
    -- FASE 7d: (correção R6) fecha o bloco da OS
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_err := v_err + 1;
      perform public.log_app_error('db', format('o local, passo combinar (%s): %s', public._agenda_rotulo_da_os(r.os), v_msg), 'agenda', 'local:combinar', 'error',
                                   jsonb_build_object('passo', 'combinar', 'os', r.os, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
    -- FASE 7d: fim
  end loop;
  v_vd := coalesce((v_r ->> 'resolvidas')::int, 0);
  return jsonb_build_object('abertas', v_ab, 'criticas', v_cr, 'resolvidas', v_vd, 'descartadas', coalesce((v_r ->> 'descartadas')::int, 0),
                            'em_teste', v_tes, 'erros', v_err);
end;
$function$;

create or replace function public._agenda_local_conflitos(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c      public.agenda_config := public._agenda_cfg();
  v_oss  uuid[];
  v_ate  date;
  v_lrs  jsonb := '[]'::jsonb;
  v_out  jsonb := '[]'::jsonb;
  v_os   uuid;
  v_lr   jsonb;
  v_lm   jsonb;
  v_rot  text;
  v_dias int[];
  v_mei  int[];
  v_sai  int;
  v_ret  date;
  v_i    int;
  v_h    int;
  v_mot  text;
  v_or   text;
  r      record;
  t      record;
  v_it   jsonb;
  v_pc   jsonb;
  v_ds   date[];
  v_n    int;
  v_util boolean[];
begin
  select coalesce(array_agg(distinct a.service_order_id order by a.service_order_id), '{}'::uuid[]), max(a.dia) into v_oss, v_ate
    from public.agenda_alocacoes a
   where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null;
  if cardinality(v_oss) = 0 then
    return v_out;
  end if;

  foreach v_os in array v_oss loop
    -- FASE 7d: (correção R6) cada OS na sua subtransação: a que lança vira um item erro (a rodada conta), e o resto da lista fica de pé
    begin
    -- FASE 7d: fim
    v_lr := public._agenda_local_resolvido(v_os, p_hoje);
    v_lrs := v_lrs || jsonb_build_array(v_lr);
    v_rot := public._agenda_rotulo_da_os(v_os);

    -- O dia fechado pelo local: a régua de _agenda_violacoes. O fixado pelo dono aparece com fica = true: ele não sai.
    v_lm := public._agenda_local_mascara(v_os, p_hoje, v_ate, p_hoje, v_lr);
    v_dias := public._agenda_ints(v_lm -> 'dias');
    v_mei := public._agenda_ints(v_lm -> 'meios');
    v_sai := coalesce((v_lm ->> 'sai')::int, 0);
    for r in
      select a.dia, array_agg(a.id order by a.id) as ids, bool_and(a.fixado_por is not distinct from 'dono') as fica
        from public.agenda_alocacoes a
       where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
       group by a.dia order by a.dia
    loop
      v_i := r.dia - p_hoje + 1;
      v_mot := null;
      if v_i = any (v_dias) then
        -- o motivo sem o parêntese da máscara (§6.2)
        v_mot := regexp_replace(v_lm -> 'motivos' ->> v_i::text, ' \([^()]*\)$', '');
        v_or := 'mascara';
      elsif v_sai > 0 and v_i >= v_sai then
        select pl.retirada_em into v_ret from public.os_planejamento pl where pl.service_order_id = v_os;
        v_mot := format('%s: o bem sai %s', public._dia_curto(r.dia), public._dia_curto(v_ret));
        v_or := 'retirada';
      end if;
      if v_mot is not null then
        v_out := v_out || jsonb_build_object('tipo', 'calendario', 'origem', v_or, 'os', v_os, 'dia', r.dia, 'turno', null, 'alocacoes', to_jsonb(r.ids),
                                             'fica', r.fica, 'motivo', v_mot, 'texto', format('%s: %s', v_rot, v_mot));
        continue;
      end if;
      -- O meio-dia fora do horário do local conferido
      for t in
        select a.turno, array_agg(a.id order by a.id) as ids, bool_and(a.fixado_por is not distinct from 'dono') as fica
          from public.agenda_alocacoes a
         where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.dia = r.dia and a.resultado is null
         group by a.turno order by a.turno = 'tarde'
      loop
        v_h := 2 * (v_i - 1) + case when t.turno = 'manha' then 1 else 2 end;
        if v_h = any (v_mei) then
          v_mot := format('%s: %s não recebe a equipe', public._agenda_meio_texto(r.dia, t.turno), coalesce(v_lr ->> 'nome', 'o local'));
          v_out := v_out || jsonb_build_object('tipo', 'calendario', 'origem', 'mascara', 'os', v_os, 'dia', r.dia, 'turno', t.turno, 'alocacoes', to_jsonb(t.ids),
                                               'fica', t.fica, 'motivo', v_mot, 'texto', format('%s: %s', v_rot, v_mot));
        end if;
      end loop;
    end loop;

    -- O acesso não combinado na véspera: só conta, não tira ninguém
    select e into v_it from jsonb_array_elements(public._agenda_combinar_da_os(v_os, p_hoje)) e where e ->> 'tipo' = 'acesso';
    if v_it is not null and not (v_it ->> 'combinado')::boolean and (v_it ->> 'para')::date > p_hoje
       and p_hoje >= public.agenda_somar_du((v_it ->> 'para')::date, -c.acesso_urgente_du) then
      v_mot := format('o acesso%s para %s ainda não está combinado', coalesce(' ' || public._agenda_local_no(v_it ->> 'local'), ''),
                      public._dia_curto((v_it ->> 'para')::date));
      v_out := v_out || jsonb_build_object('tipo', 'acesso', 'os', v_os, 'dia', v_it ->> 'para', 'fica', true, 'motivo', v_mot,
                                           'texto', format('%s: %s', v_rot, v_mot));
    end if;

    -- A viagem com pernoite quebrada: dias úteis seguidos, com a mesma equipe
    if public._agenda_viagem_da_os(v_os, p_hoje, v_lr) ->> 'tipo' = 'pernoite' then
      v_ds := array(select distinct a.dia from public.agenda_alocacoes a
                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                     order by 1);
      v_n := cardinality(v_ds);
      if v_n > 1 and (exists (select 1 from generate_series(1, v_n - 1) g(i) where public.agenda_du_entre(v_ds[g.i], v_ds[g.i + 1]) <> 1)
                      or (select count(distinct x.eq) from (
                            select string_agg(a.payee_id::text, ',' order by a.payee_id) as eq
                              from public.agenda_alocacoes a
                             where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                               and a.presenca = 'turno'
                             group by a.dia, a.turno) x) > 1) then
        v_mot := format('a viagem precisa de %s dias úteis seguidos com a mesma equipe', v_n);
        v_out := v_out || jsonb_build_object('tipo', 'viagem', 'os', v_os, 'dia', v_ds[1], 'fica', false, 'motivo', v_mot,
                                             'texto', format('%s: %s', v_rot, v_mot));
      end if;
    end if;
    -- FASE 7d: (correção R6) fecha o bloco da OS. v_lrs anda junto de v_oss (o contexto do pátio lê pela posição): quem caiu antes de entrar na lista entra nulo
    exception when others then
      v_out := v_out || jsonb_build_object('tipo', 'erro', 'os', v_os, 'erro', left(sqlerrm, 300), 'sqlstate', sqlstate, 'fica', true);
      if jsonb_array_length(v_lrs) < array_position(v_oss, v_os) then
        v_lrs := v_lrs || 'null'::jsonb;
      end if;
    end;
    -- FASE 7d: fim
  end loop;

  -- O pátio acima das vagas: em cada dia, quem chegou depois das vagas (a ocupação do motor, _agenda_patio_contexto). Até o último dia do plano: depois dele ninguém
  -- chega, e quem já estava junto já contou.
  v_util := array(select public.agenda_dia_util(p_hoje + g.d) from generate_series(0, v_ate - p_hoje) g(d) order by g.d);
  v_pc := public._agenda_patio_contexto(p_hoje, v_ate, p_hoje, v_oss, v_lrs, '{}'::uuid[], v_util);
  for r in
    select distinct on (y.k, y.i) y.k, y.i, y.d
      from (select x.k, x.i, g.d, row_number() over (partition by x.k, g.d order by x.d1, x.i) as pos
              from (select (e ->> 'k')::int as k, (e ->> 'i')::int as i, (e ->> 'd1')::int as d1, (e ->> 'd2')::int as d2
                      from jsonb_array_elements(v_pc -> 'pat_int') e) x
             cross join lateral generate_series(x.d1, x.d2) g(d)) y
     where y.pos > (v_pc -> 'pat_max' ->> (y.k - 1))::int
     order by y.k, y.i, y.d
  loop
    continue when r.i < 1;
    v_mot := format('%s: %s', public._dia_curto(p_hoje + r.d - 1),
                    public._agenda_patio_frase(v_pc -> 'pat_nomes' ->> (r.k - 1), (v_pc -> 'pat_max' ->> (r.k - 1))::int, true));
    v_out := v_out || jsonb_build_object('tipo', 'patio', 'os', v_oss[r.i], 'dia', p_hoje + r.d - 1, 'fica', false, 'motivo', v_mot,
                                         'texto', format('%s: %s', public._agenda_rotulo_da_os(v_oss[r.i]), v_mot));
  end loop;
  return v_out;
end;
$function$;

create or replace function public._agenda_local_calendario(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_patio  boolean := public._agenda_local_modo('patio') = 'ligado';
  v_oss    uuid[];
  v_os     uuid;
  -- FASE 7d: (correção C1) a rede K: conta antes de mover
  cf       public.agenda_config := public._agenda_cfg();
  v_lista  jsonb := public._agenda_local_conflitos(p_hoje);
  v_avis   int;
  v_onda   boolean := false;
  -- FASE 7d: fim
  v_r      jsonb;
  v_ok     int := 0;
  v_err    int := 0;
  v_estado text;
  v_msg    text;
begin
  v_oss := array(select distinct (e ->> 'os')::uuid
                   from jsonb_array_elements(v_lista) e
                  where e ->> 'tipo' = 'calendario' and not (e ->> 'fica')::boolean and (e ->> 'origem' = 'mascara' or v_patio)
                  order by 1);
  -- FASE 7d: (correção C1) a onda conta por proposta (_agenda_propor_e_aplicar): OS por OS ela nunca dispararia. Acima de gestor_k_os, ou de gestor_k_dias_avisados dias já avisados, UMA
  -- chamada com o array todo: a onda nasce como no resto. Abaixo disso, OS por OS, com o isolamento de sempre.
  select count(distinct a.dia)::int into v_avis
    from jsonb_array_elements(v_lista) e
   cross join lateral jsonb_array_elements_text(e -> 'alocacoes') i(id)
    join public.agenda_alocacoes a on a.id = i.id::uuid
   where e ->> 'tipo' = 'calendario' and not (e ->> 'fica')::boolean and (e ->> 'origem' = 'mascara' or v_patio)
     and public._agenda_dia_avisado(a.payee_id, a.service_order_id, a.dia) is not null;
  if cardinality(v_oss) > cf.gestor_k_os or v_avis > cf.gestor_k_dias_avisados then
    begin
      perform set_config('agenda.local_violacao', 'on', true);
      v_r := public.agenda_replanejar(v_oss, 'local', 'vigia', p_hoje, p_agora);
      perform set_config('agenda.local_violacao', '', true);
      v_onda := coalesce((v_r ->> 'onda')::boolean, false);
      if coalesce((v_r ->> 'ok')::boolean, false) then
        v_ok := cardinality(v_oss);
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_err := v_err + 1;
      perform public.log_app_error('db', format('o local, passo calendario (%s OS juntas): %s', cardinality(v_oss), v_msg), 'agenda', 'local:calendario',
                                   'error', jsonb_build_object('passo', 'calendario', 'os', to_jsonb(v_oss), 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
    return jsonb_build_object('os', cardinality(v_oss), 'replanejadas', v_ok, 'erros', v_err, 'onda', v_onda);
  end if;
  -- FASE 7d: fim
  foreach v_os in array v_oss loop
    begin
      perform set_config('agenda.local_violacao', 'on', true);
      v_r := public.agenda_replanejar(array[v_os], 'local', 'vigia', p_hoje, p_agora);
      perform set_config('agenda.local_violacao', '', true);
      if coalesce((v_r ->> 'ok')::boolean, false) then
        v_ok := v_ok + 1;
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_err := v_err + 1;
      perform public.log_app_error('db', format('o local, passo calendario (%s): %s', public._agenda_rotulo_da_os(v_os), v_msg), 'agenda', 'local:calendario',
                                   'error', jsonb_build_object('passo', 'calendario', 'os', v_os, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;
  return jsonb_build_object('os', cardinality(v_oss), 'replanejadas', v_ok, 'erros', v_err);
end;
$function$;

create or replace function public.agenda_local_vigiar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos constant text[] := array['calendario', 'combinar', 'conflitos'];
  cf       public.agenda_config;
  v_t0     timestamptz := clock_timestamp();
  v_modos  jsonb;
  v_passo  text;
  v_r      jsonb;
  v_cont   jsonb := '{}'::jsonb;
  v_erros  int := 0;
  v_falhas jsonb := '[]'::jsonb;
  v_estado text;
  v_msg    text;
  -- FASE 7d: (correção R6) a rodada com erro tenta de novo no tique seguinte, até 3 vezes por dia
  c_tentativas constant int := 3;   -- decisão do fio (R6): depois disso, app_error_logs
  v_tent   int;
  -- FASE 7d: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada do local.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_local'));
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('calendario', public._agenda_local_modo('calendario'), 'acesso', public._agenda_local_modo('acesso'),
                                'bem', public._agenda_local_modo('bem'), 'patio', public._agenda_local_modo('patio'),
                                'viagem', public._agenda_local_modo('viagem'), 'mesmo_local', public._agenda_local_modo('mesmo_local'));

  -- A cada tique, só com pergunta aberta: o acesso que entrou resolve a pergunta antes do fechamento (R1). Sem pergunta, uma consulta só.
  if exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' and q.tipo in ('combinar', 'acesso')) then
    begin
      perform public._agenda_local_resolver(p_hoje, p_agora);
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      perform public.log_app_error('db', format('o local, passo resolver: %s', v_msg), 'agenda', 'local:resolver', 'error',
                                   jsonb_build_object('passo', 'resolver', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end if;

  -- FASE 7d: (correção O5) "eu te aviso": a cada tique, só com o modo ligado (em teste, nenhuma leitura). Fora da rodada do dia: o acesso vira combinado a qualquer hora
  if v_modos ->> 'acesso' = 'ligado' then
    begin
      perform public._agenda_local_avisar_acesso(p_hoje, p_agora);
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      perform public.log_app_error('db', format('o local, passo aviso do acesso: %s', v_msg), 'agenda', 'local:aviso', 'error',
                                   jsonb_build_object('passo', 'aviso', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end if;
  -- FASE 7d: fim
  if not exists (select 1 from jsonb_each_text(v_modos) m where m.value <> 'desligado') then
    return jsonb_build_object('rodou', false, 'modos', v_modos);
  end if;
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.local_hora then
    return jsonb_build_object('rodou', false, 'cedo', true, 'modos', v_modos, 'hora', cf.local_hora);
  end if;
  -- (correção R6) só a rodada sem erro vale como feita; a com erro tenta de novo no tique seguinte, até 3 vezes no dia
  select count(*)::int into v_tent from public.agenda_vigia_rodadas x where x.rotina = 'local' and x.p_hoje = p_hoje;
  if v_tent >= c_tentativas or exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'local' and x.p_hoje = p_hoje and x.erros = 0) then
    return jsonb_build_object('rodou', false, 'ja_rodou', true, 'modos', v_modos);
  end if;

  -- calendario primeiro: o combinar olha o plano já replanejado. calendario só com o modo ligado; conflitos só conta.
  foreach v_passo in array c_passos loop
    continue when v_passo = 'calendario' and v_modos ->> 'calendario' <> 'ligado';
    begin
      if v_passo = 'calendario' then
        v_r := public._agenda_local_calendario(p_hoje, p_agora);
        v_erros := v_erros + coalesce((v_r ->> 'erros')::int, 0);
      elsif v_passo = 'combinar' then
        v_r := public._agenda_local_combinar(p_hoje, p_agora);
        v_erros := v_erros + coalesce((v_r ->> 'erros')::int, 0);   -- (correção R6)
      else
        v_r := (select coalesce(jsonb_object_agg(x.tipo, x.n), '{}'::jsonb)
                  from (select e ->> 'tipo' as tipo, count(*) as n
                          from jsonb_array_elements(public._agenda_local_conflitos(p_hoje)) e group by 1) x);
        v_erros := v_erros + coalesce((v_r ->> 'erro')::int, 0);   -- (correção R6)
      end if;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('o local, passo %s: %s', v_passo, v_msg), 'agenda', 'local:' || v_passo, 'error',
                                   jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('modos', v_modos, 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'local', cf.modo_equipe, cf.modo_diaria);

  -- (correção R6) a última tentativa do dia com erro: fica consultável, com o que faltou
  if v_erros > 0 and v_tent + 1 >= c_tentativas then
    perform public.log_app_error('db', format('o local: a rodada de %s falhou %s vezes e só volta amanhã', to_char(p_hoje, 'DD/MM'), c_tentativas), 'agenda', 'local:rodada', 'error',
                                 jsonb_build_object('erros', v_erros, 'falhas', v_falhas, 'p_hoje', p_hoje, 'p_agora', p_agora));
  end if;
  return jsonb_build_object('rodou', true, 'modos', v_modos, 'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas);
end;
$function$;

create or replace function public._agenda_cliente_onde_fica(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  c_du_min constant int := 2;   -- §5.6: a menos disso, a véspera e o M4 perguntam o acesso
  v_modo   text := case when cf.modo_cliente = 'ligado' and 'onde_fica' = any (cf.cliente_tipos_ligados) then 'ligado' else 'sombra' end;
  r        record;
  v_motivo text;
  v_classe text;
  v_dia    date;
  v_var    text;
  v_dados  jsonb;
  v_txt    text;
  v_parte  text;
  v_envio  date;
  v_seg    date;
  v_r      jsonb;
  n_reg    int := 0;
  n_erro   int := 0;
  v_pul    jsonb := '{}'::jsonb;
begin
  -- R6.7b: a porta do 1º dia confia no plano, e com o freio o plano é o que está em dúvida
  if cf.gestor_so_propor then
    return jsonb_build_object('pulado', 'gestor_so_propor');
  end if;
  -- R6.7a-1, R6.8-7: nula = ninguém, e nenhuma leitura
  if cf.onde_fica_desde is null then
    return jsonb_build_object('registradas', 0, 'puladas', v_pul, 'erros', 0);
  end if;

  -- onde_fica_desde filtra antes do cálculo. Em ligado e em teste: nas duas portas. A OS que já tem o M11 deste modo também sai aqui: é uma por OS na vida.
  for r in
    select k.service_order_id as os, k.aprovada_em, so.client_id
      from public.os_carteira(p_hoje) k
      join public.service_orders so on so.id = k.service_order_id
     where k.aprovada_em >= cf.onde_fica_desde
       and not exists (select 1 from public.agenda_cliente_mensagens m
                        where m.service_order_id = k.service_order_id and m.tipo = 'onde_fica' and m.modo = v_modo)
     order by k.numero collate "C", k.service_order_id
  loop
    begin
      v_motivo := public._agenda_cliente_ja_atendida(r.os);
      if v_motivo is null then
        select min(a.dia) into v_dia from public.agenda_alocacoes a
         where a.service_order_id = r.os and a.estado in ('publicada', 'fixada');
        v_classe := public._agenda_cliente_onde_falta(r.os, p_hoje);
        v_motivo := case
          -- o plano diz que já começou (ou começa hoje): a porta da aprovação não pergunta "para eu deixar encaminhado" a esse cliente
          when v_dia <= p_hoje then 'plano_comecou'
          when v_classe is null then 'nada_a_perguntar'
          when not (r.aprovada_em >= p_hoje - cf.onde_fica_janela_dias
                    or coalesce(v_dia <= p_hoje + cf.onde_fica_antes_dias and public.agenda_du_entre(p_hoje, v_dia) > c_du_min, false))
            then 'fora_da_janela'
        end;
      end if;
      if v_motivo is null then
        -- R6.9-5: o registrar LANÇA acima do teto. O texto aprovado sem uma parte opcional, sem palavra nova
        v_var := case when v_classe = 'barco' then 'barco' else 'motorhome' end;
        v_dados := jsonb_build_object('chave', 'unica',
          'primeira', (public._agenda_cliente_contexto(r.os, p_hoje) ->> 'primeira')::boolean,
          'uso', v_classe = 'rv' or extract(month from p_hoje)::smallint = any (cf.temporada_meses),
          'prazo', v_classe = 'barco'
                   and not exists (select 1 from public.os_planejamento p where p.service_order_id = r.os and p.precisa_ate is not null));
        v_txt := public._agenda_cliente_texto('onde_fica', v_var, r.os, v_dados, p_hoje);
        foreach v_parte in array array['prazo', 'uso'] loop
          exit when public._agenda_cliente_texto_proibido(v_txt) is distinct from 'tamanho';
          if (v_dados ->> v_parte)::boolean then
            v_dados := v_dados || jsonb_build_object(v_parte, false);
            v_txt := public._agenda_cliente_texto('onde_fica', v_var, r.os, v_dados, p_hoje);
          end if;
        end loop;
        if public._agenda_cliente_texto_proibido(v_txt) = 'tamanho' then
          v_motivo := 'tamanho';
        end if;
      end if;
      if v_motivo is null then
        -- O M11 cede o dia: o teto recusa de vez (a chave do M1 é a do dia, a do M11 é única), e nenhuma das duas volta. Quem cede é o M11, que tenta de novo no
        -- tique seguinte. Conta também o que ainda não entrou na fila; a mesma regra do mesmo tipo em 24 h, que a revalidação recusaria.
        v_envio := (public._agenda_cliente_quando(hashtext(r.os::text), p_agora, p_agora) at time zone 'America/Sao_Paulo')::date;
        v_seg := date_trunc('week', v_envio)::date;
        if (select count(*) from public.agenda_cliente_mensagens m
             where m.client_id = r.client_id and m.modo = 'ligado'
               and m.estado in ('registrada', 'aguardando_dono', 'enfileirada', 'enviada', 'respondida', 'sem_resposta')
               and (m.enviar_em at time zone 'America/Sao_Paulo')::date = v_envio) >= cf.cliente_dia_max
           or public._agenda_cliente_no_periodo(r.client_id, v_seg, v_seg + 6, null) >= cf.cliente_semana_max
           or exists (select 1 from public.agenda_cliente_mensagens m
                       where m.client_id = r.client_id and m.tipo = 'onde_fica' and m.enviada_em is not null
                         and m.enviada_em > p_agora - make_interval(hours => cf.cliente_mesmo_tipo_horas)) then
          v_motivo := 'cliente_ja_tem_mensagem';
        end if;
      end if;
      if v_motivo is null then
        v_r := public._agenda_cliente_registrar('onde_fica', v_var, r.os, null, v_dados, p_agora, null, 'rodada', null, p_agora);
        if coalesce((v_r ->> 'criada')::boolean, false) then
          n_reg := n_reg + 1;
          -- (correção R5) o M11 em teste nasce contado, como a rodada do local: a ação fica no foco, e não ocupa linha do fechamento
          if v_r ->> 'modo' = 'sombra' then
            update public.agenda_acoes a set contada_em = p_agora
             where a.id = (select m.acao_id from public.agenda_cliente_mensagens m where m.id = (v_r ->> 'id')::uuid);
          end if;
        else
          v_motivo := coalesce(v_r ->> 'motivo', v_r ->> 'modo', 'nao_criada');
        end if;
      end if;
      if v_motivo is not null then
        v_pul := v_pul || jsonb_build_object(v_motivo, coalesce((v_pul ->> v_motivo)::int, 0) + 1);
      end if;
    exception when others then
      perform public._agenda_cliente_erro_da_os('onde_fica', r.os, sqlstate, sqlerrm, p_hoje);
      n_erro := n_erro + 1;
    end;
  end loop;
  return jsonb_build_object('registradas', n_reg, 'puladas', v_pul, 'erros', n_erro);
end;
$function$;

create or replace function public._agenda_local_proposto(p_os uuid, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_t    text := public._agenda_normal(normalize(coalesce(p_trecho, ''), nfc));
  v_ids  uuid[];
  l      public.agenda_locais;
  v_sit  text;
  v_quem text;
begin
  select coalesce(array_agg(x.id), '{}'::uuid[]) into v_ids
    from public.agenda_locais x
   where x.ativo and x.tipo <> 'casa_cliente'   -- (correção O3) a casa de um cliente não é lugar que outro cite
     and exists (select 1 from unnest(x.apelidos || x.nome) a(t)
                  where char_length(public._agenda_normal(normalize(a.t, nfc))) >= 3
                    and v_t ~ ('\m' || public._agenda_normal(normalize(a.t, nfc)) || '\M'));
  if cardinality(v_ids) = 1 then
    select * into l from public.agenda_locais x where x.id = v_ids[1];
  end if;

  -- \M também: "fico no aguardo" não é água, "secador" não é seco
  if v_t ~ '\m(agua|molhad\w*|pier|flutuante)\M' then
    v_sit := 'agua';
  elsif v_t ~ '\m(garagem|hangar|empilhadeira|vaga seca|seco|seca|em terra|carreta)\M' then
    -- o local que o cliente disse manda, mesmo sem a garagem dita: o da OS é outro lugar
    v_sit := case when coalesce(case when l.id is not null then l.tem_garagem_seca
                                     else (select x.tem_garagem_seca from public.agenda_locais x
                                            where x.id = (public._agenda_local_resolvido(p_os, p_hoje) ->> 'local_id')::uuid) end, false)
                  then 'garagem_seca' else 'seco' end;
  elsif v_t ~ '\m(patio|com voces|levo|trago|deixo ai)\M' then
    v_sit := 'patio';
  end if;

  v_quem := case when v_t ~ '\mmarinheiro\M' then 'o marinheiro'
                 when v_t ~ '\m(a marina|o pessoal da marina|marina desce)\M' then 'a marina'
                 when v_t ~ '\m(eu (mesmo )?desco|eu levo)\M' then 'o cliente' end;

  return jsonb_build_object('local_id', l.id, 'local_nome', l.nome, 'situacao', v_sit, 'descer_quem', v_quem,
    -- (correção R3) a resposta fala de lugar? O leitor achou alguma coisa, ou há palavra de lugar. "sim", "quanto custa?" e "não quero mais" não falam
    'sinal', l.id is not null or v_sit is not null or v_quem is not null or cardinality(v_ids) > 0
             or v_t ~ '\m(marina|estaleiro|iate|clube|hangar|garagem|casa|sitio|chacara|fazenda|condominio|rua|avenida|bairro|praia|cais|trapiche|galpao|oficina|porto|cidade)\M'
             or v_t ~ '\m(esta|ta|fica|ficou|deixei|deixo) (ai|aqui|la|ali|com voces)\M'
             or exists (select 1 from public.agenda_locais x where x.ativo and x.municipio is not null
                         and v_t ~ ('\m' || public._agenda_normal(normalize(x.municipio, nfc)) || '\M')),
    'entendi', nullif(concat_ws(', ', l.nome,
                                case v_sit when 'agua' then 'na água' when 'seco' then 'em seco' when 'garagem_seca' then 'em seco (garagem)'
                                           when 'patio' then 'no pátio' end,
                                'quem desce: ' || v_quem), ''));
end;
$function$;

create or replace function public._agenda_cliente_anotar_onde(p_msg uuid, p_resposta uuid, p_trecho text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_validade constant interval := interval '7 days';   -- §5.6: a pergunta local some em 7 dias
  m       public.agenda_cliente_mensagens%rowtype;
  x       jsonb;
  v_prop  jsonb;
  v_os    uuid;
  v_nome  text;
  v_bem   text;
  v_disse text;
  v_antes text;
  v_dep   text;
  v_linha text;
  v_ok    timestamptz;
  v_txt   text;
  v_acao  uuid;
  v_perg  uuid;
  v_q     text;
  v_opc2  jsonb := jsonb_build_object('n', 2, 'texto', 'Não gravo, eu te digo como é', 'efeito', jsonb_build_object('local', 'nada'));
  v_t     text;   -- (correção R3)
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  v_os := m.service_order_id;
  x := public._agenda_cliente_contexto(v_os, p_hoje);
  v_nome := coalesce(x ->> 'nome', 'cliente');
  v_bem := regexp_replace(regexp_replace(x ->> 'bem', '^seu ', 'o '), '^sua ', 'a ');   -- ao dono: "o veleiro", "a lancha", "o Brisa"
  v_disse := public._agenda_corta(btrim(coalesce(p_trecho, '')), 200);

  -- FASE 7d: (correção R3, R4, O19) só o que fala de lugar é resposta ao M11. Sem sinal, nada é anotado: nem site_access (a via do técnico), nem acesso_conhecido (a pergunta da chave segue
  -- saindo). Volta ao dono como resposta comum, e a desistência chega como desistência. Com um dia e sem lugar, a pergunta diz que ele respondeu sem dizer onde.
  v_prop := public._agenda_local_proposto(v_os, p_trecho, p_hoje);
  if not coalesce((v_prop ->> 'sinal')::boolean, false) then
    v_t := public._agenda_normal(normalize(coalesce(p_trecho, ''), nfc));
    return jsonb_build_object('ok', false, 'sem_lugar', true,
      'o_que', case when v_t ~ '\m(nao quero mais|desist\w*|cancel\w*|nao vou mais|deixa pra la|nao preciso mais)\M' then 'parece que desistiu do serviço'
                    when public._agenda_preparar_data(coalesce(p_trecho, '')) !~ '(\mdia \d{1,2}\M|\m\d{1,2}/\d{1,2})' then 'não disse onde fica' end,
      'texto', case when public._agenda_preparar_data(coalesce(p_trecho, '')) ~ '(\mdia \d{1,2}\M|\m\d{1,2}/\d{1,2})'
                         and v_t !~ '\m(nao quero mais|desist\w*|cancel\w*|nao vou mais|deixa pra la|nao preciso mais)\M'
                    then format('%s respondeu sem dizer onde fica %s: "%s". Me diga onde é, por exemplo: "o serviço do %s é na Marina Itajaí".', v_nome, v_bem, v_disse, v_nome) end);
  end if;
  -- FASE 7d: fim

  -- R6.3-5: a linha e a ação de sempre, com efeito anotou_acesso (o *desfaz* já conhece). acesso_ok_em NÃO muda: antes e depois levam o valor de antes.
  -- Se contasse, gravaria o acesso por cliente_acesso_validade_dias, e a crítica de véspera nunca nasceria.
  select so.site_access into v_antes from public.service_orders so where so.id = v_os for update;
  v_linha := format('Cliente (%s): %s', to_char(p_hoje, 'DD/MM'), left(btrim(coalesce(p_trecho, '')), 300));
  v_dep := case when coalesce(v_antes, '') = '' then v_linha else v_antes || E'\n' || v_linha end;
  update public.service_orders set site_access = v_dep where id = v_os;
  select pl.acesso_ok_em into v_ok from public.os_planejamento pl where pl.service_order_id = v_os;
  v_txt := format('Anotei o que %s disse sobre onde fica %s: "%s".', v_nome, v_bem, v_disse);
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   motivo, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, 'cliente', 'cliente', v_os, array[v_os],
          jsonb_build_object('site_access', v_antes, 'acesso_ok_em', v_ok),
          jsonb_build_object('efeito', 'anotou_acesso', 'resposta_id', p_resposta, 'mensagem_id', m.id,
                             'site_access', v_dep, 'acesso_ok_em', v_ok, 'linha', v_linha),
          public._agenda_corta(v_txt, 400), 'o cliente disse onde fica', p_agora + cf.desfazer_validade)
  returning id into v_acao;

  -- A pergunta ao dono: o vínculo com o local nunca é gravado sem ele
  if v_prop ->> 'entendi' is not null then
    v_q := format('%s respondeu onde fica %s: "%s". Entendi: %s. 1) Gravo assim (recomendo); 2) Não gravo, eu te digo como é.',
                  v_nome, v_bem, v_disse, v_prop ->> 'entendi');
  else
    v_q := format('%s respondeu onde fica %s: "%s". Não achei esse lugar no cadastro. Me diga onde é, por exemplo: "o serviço do %s é na Marina Itajaí".', v_nome, v_bem, v_disse, v_nome);
  end if;
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, recomendacao, modo, criada_em, expira_em)
  values ('local', 'local:' || v_os, v_os, array[v_os], left(public._agenda_corta(v_q, 600), 600),
          case when v_prop ->> 'entendi' is not null
               then jsonb_build_array(jsonb_build_object('n', 1, 'texto', 'Gravo assim', 'efeito', jsonb_build_object('local', 'gravar',
                      'item', (v_prop - 'entendi') || jsonb_build_object('cliente', v_nome, 'bem', v_bem))), v_opc2)
               else jsonb_build_array(v_opc2) end,
          case when v_prop ->> 'entendi' is not null then 1 end, 'ligado', p_agora, p_agora + c_validade)
  on conflict (chave, modo) where estado = 'aberta' do nothing
  returning id into v_perg;
  if v_perg is null then
    select q.id into v_perg from public.agenda_perguntas q where q.chave = 'local:' || v_os and q.modo = 'ligado' and q.estado = 'aberta';
  end if;

  -- O bem_livre do 7a: o dono deixa de esperar (R2)
  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'o cliente respondeu onde fica'
   where chave = 'bem_livre:' || v_os and estado = 'aberta';

  return jsonb_build_object('ok', true, 'acao_id', v_acao, 'pergunta_id', v_perg, 'texto', public._agenda_corta(v_txt, 400));
end;
$function$;

create or replace function public._agenda_cliente_revalidar(p_msg uuid, p_agora timestamptz default now())
 returns text
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  m      public.agenda_cliente_mensagens%rowtype;
  so     record;
  v_hoje date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_plano jsonb;
  v_agora_dia date;
  v_nivel text;
  v_txt  text;
  v_dados jsonb;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  if not found then
    return 'desatualizada';
  end if;
  -- 1. o cliente pediu para não receber (ou o cadastro saiu)
  if public._agenda_cliente_sem_mensagem(m.client_id) then
    return 'opt_out';
  end if;
  -- CORREÇÃO FASE 5: (item 13) 1b. o d10 também na revalidação — e por isso no gatilho da fila (as duas travas) e no
  -- agenda_cliente_pode_sair (o worker): a quem não escreveu para a HBR em cliente_conversa_dias a mensagem não sai, por
  -- qualquer caminho. Sem telefone válido, o motivo verdadeiro é o telefone (como no enfileirar).
  if not public._agenda_cliente_conversou(m.client_id, p_agora) then
    return case when public._agenda_cliente_telefone(m.client_id) is null then 'sem_telefone' else 'sem_conversa' end;
  end if;
  -- CORREÇÃO FASE 5: fim
  -- 2. o status da OS
  select o.status, o.delivered_at, o.scheduled_start_at, o.scheduled_end_at into so
    from public.service_orders o where o.id = m.service_order_id;
  -- CORREÇÃO FASE 5: (item 24) a OS faturada (invoiced) logo depois de concluída vale como concluída — o resto da Fase 5
  -- já a trata assim (a resposta, o cliente_avisar): o "ficou pronto" e o pós-serviço dela saem; o aviso de atraso não
  if found and so.status = 'invoiced' then
    so.status := 'completed';
  end if;
  -- CORREÇÃO FASE 5: fim
  if not found or so.status in ('cancelled', 'draft')
     or (m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         and so.status in ('awaiting_parts', 'awaiting_client', 'completed'))
     or (m.tipo = 'andamento' and so.status <> 'in_progress')
     or (m.tipo in ('pronto', 'pronto_lembrete') and (so.status <> 'completed' or so.delivered_at is not null))
     or (m.tipo = 'pos_servico' and so.status <> 'completed')
     or (m.tipo = 'pode_atrasar' and so.status = 'completed') then
    return 'status';
  end if;
  -- FASE 7d: (7d P6; R6.7a-3, §5.6) o M11, na hora de sair: a OS é relida. O que já foi feito não recebe; o que já foi dito perdeu o sentido
  if m.tipo = 'onde_fica' then
    -- (correção C2) parar o M11 (onde_fica_desde nula) recusa também o que está na fila, como tirar o tipo da lista
    if cf.onde_fica_desde is null then
      return 'tipo_em_teste';
    end if;
    if public._agenda_cliente_ja_atendida(m.service_order_id) is not null then
      return 'status';
    end if;
    if public._agenda_cliente_onde_falta(m.service_order_id, v_hoje) is null then
      return 'desatualizada';
    end if;
  end if;
  -- FASE 7d: fim
  -- 3. a data: o dia de que a mensagem fala (o próximo dia do plano; sem plano no registro, o dia agendado da OS) e, nos
  -- tipos de fim (o andamento e o atraso da execução), o último dia
  v_plano := public._agenda_plano_da_os(m.service_order_id, v_hoje);
  if m.base ? 'dia_alvo'
     and (m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
          or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado')) then
    v_agora_dia := case when m.base ->> 'referencia' = 'agendada'
                        then (so.scheduled_start_at at time zone 'America/Sao_Paulo')::date
                        else (v_plano ->> 'proximo_dia')::date end;
    if v_agora_dia is distinct from (m.base ->> 'dia_alvo')::date then
      return 'data_mudou';
    end if;
  end if;
  if m.base ? 'fim' and m.base ->> 'referencia' = 'plano'
     and (m.tipo = 'andamento' or (m.tipo = 'pode_atrasar' and m.variante = 'execucao'))
     and (v_plano ->> 'ultimo_dia')::date is distinct from (m.base ->> 'fim')::date then
    return 'data_mudou';
  end if;
  -- CORREÇÃO FASE 5: (item 6) o remarcado em que só o fim mudou (a forma fim) diz o fim: o último dia de agora tem de ser
  -- o dele. (item 7) a data firme que o DONO mandou dizer (cliente_avisar firme: base.dados.firme_do_dono) não passa pelo
  -- passo 4 — o d09 deixa o dono trocar a faixa pela data firme do plano; os passos 1–3 e 5–7 continuam
  if m.tipo = 'pode_atrasar' and m.variante = 'remarcado' and m.base #>> '{dados,forma}' = 'fim'
     and (v_plano ->> 'ultimo_dia')::date is distinct from (m.base ->> 'fim')::date then
    return 'data_mudou';
  end if;
  if m.origem = 'dono' and coalesce((m.base #>> '{dados,firme_do_dono}')::boolean, false) then
    m.prometido_tipo := null;   -- só nesta cópia local: o passo 4, abaixo, não vale para ela
  end if;
  -- CORREÇÃO FASE 5: fim
  -- 4. a data firme sem todo o material crítico na mão (d09): o pior nível dos críticos fora de A
  if m.prometido_tipo = 'firme' then
    v_nivel := public.os_prontidao(m.service_order_id, v_hoje) #>> '{material,confianca}';
    if v_nivel is not null and v_nivel <> 'A' then
      return 'material';
    end if;
  end if;
  -- 5. o aviso de atraso depois da data que o cliente ouviu (não sai: vira pergunta crítica na rodada)
  if m.tipo = 'pode_atrasar'
     and exists (select 1 from public.os_planejamento p
                  where p.service_order_id = m.service_order_id and p.prometido_ate < v_hoje) then
    return 'passou_da_data';
  end if;
  -- 6. o mesmo tipo a este cliente nas últimas cliente_mesmo_tipo_horas
  if exists (select 1 from public.agenda_cliente_mensagens x
              where x.client_id = m.client_id and x.tipo = m.tipo and x.id <> m.id and x.enviada_em is not null
                and x.enviada_em > p_agora - make_interval(hours => cf.cliente_mesmo_tipo_horas)) then
    return 'mesmo_tipo_24h';
  end if;
  -- 7. o texto de agora (os mesmos dados, a mesma 1ª mensagem, o dia do envio de agora) ≠ o registrado
  v_dados := coalesce(m.base -> 'dados', '{}'::jsonb)
             || jsonb_build_object('primeira', coalesce((m.base ->> 'primeira')::boolean, false),
                                   'envio', (m.enviar_em at time zone 'America/Sao_Paulo')::date);
  begin
    v_txt := public._agenda_cliente_texto(m.tipo, m.variante, m.service_order_id, v_dados, v_hoje);
  exception when others then
    return 'desatualizada';
  end;
  if v_txt is distinct from m.texto then
    return 'desatualizada';
  end if;
  return null;
end;
$function$;

create or replace function public.agenda_resposta_do_cliente(p_phone text, p_body text, p_message_id uuid, p_tipo_msg text,
                                                             p_intencao text, p_expressao text,
                                                             p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  c_pergunta_dias constant interval := interval '7 days';   -- spec §3.2: a cliente_resposta some em 7 dias
  -- os tipos que esperam resposta (spec §5.4); os que propõem um dia (o pedido de outro dia só vale neles)
  c_esperam constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia',
                                     -- FASE 7d: (7d P6, §5.6) o M11 espera resposta
                                     'onde_fica',
                                     -- FASE 7d: fim
                                     'pode_atrasar', 'pronto', 'pronto_lembrete', 'pos_servico'];
  c_do_dia  constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia'];
  v_hoje    date;
  v_modo    text;
  v_tipo    text;
  v_trecho  text;
  v_cli     uuid[];
  m         public.agenda_cliente_mensagens%rowtype;
  v_n       int;
  v_r       public.agenda_cliente_respostas%rowtype;
  v_rid     uuid := gen_random_uuid();
  v_int     text;
  v_expr    text;
  v_data    jsonb;
  v_nome    text;
  v_dia     date;
  v_ref     text;
  v_do_dia  boolean;
  v_efeito  text;
  v_o_que   text;
  v_texto   text;
  v_x       jsonb;
  v_acao    uuid;
  v_perg    uuid;
  v_acorde  boolean := false;
  v_de      date;
  v_ate     date;
  v_id      uuid;
  v_k       int := 0;
  v_estado  text;
  v_msg     text;
  -- CORREÇÃO FASE 5: a outra conversa (A1) e o PARAR que vale sempre (item 2)
  c_opt_out_dias constant interval := interval '30 days';   -- decisão da correção C1: o PARAR de quem recebeu da agenda em 30 dias
  v_outra   boolean := false;
  v_opt_cli uuid[];
  v_opt_msg uuid;
  v_opt_os  uuid;
  v_c       uuid;
  -- CORREÇÃO FASE 5: fim
  -- FASE 7d: (correção R3) a confirmação do dia pendente, atrás do M11
  v_7d_m1   public.agenda_cliente_mensagens%rowtype;
  -- FASE 7d: fim
begin
  if p_agora is null then
    return jsonb_build_object('consumiu', false);
  end if;
  -- desligado: nada lê (o webhook segue como sempre)
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('consumiu', false, 'modo', 'desligado');
  end if;
  v_tipo := case when p_tipo_msg in ('text', 'audio', 'image', 'document', 'video') then p_tipo_msg else 'outro' end;
  v_trecho := nullif(left(btrim(coalesce(p_body, '')), 500), '');
  if v_tipo = 'text' and v_trecho is null then
    return jsonb_build_object('consumiu', false);
  end if;
  v_hoje := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_modo := case when cf.modo_cliente = 'ligado' then 'ligado' else 'sombra' end;

  -- quem é (o dono, a equipe e quem recebe diária nunca são cliente)
  v_cli := public._agenda_clientes_do_telefone(p_phone, p_agora);
  if cardinality(v_cli) = 0 then
    return jsonb_build_object('consumiu', false);
  end if;
  -- a mesma mensagem dele de novo: nada muda
  if p_message_id is not null then
    select * into v_r from public.agenda_cliente_respostas r where r.whatsapp_message_id = p_message_id;
    if found then
      return jsonb_build_object('consumiu', v_r.modo = 'ligado', 'efeito', v_r.efeito, 'repetida', true, 'resposta_id', v_r.id);
    end if;
  end if;

  -- a que mensagem ele responde: a última da agenda mandada a ele (em teste, a que teria saído), dos tipos que esperam
  -- resposta, dentro de cliente_resposta_validade, ainda sem resposta. Sem ela, a agenda não lê: é conversa.
  select count(distinct x.service_order_id)::int into v_n
    from public.agenda_cliente_mensagens x
   where x.client_id = any (v_cli) and x.tipo = any (c_esperam)
     and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
           and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
          or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
              and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade));
  select x.* into m
    from public.agenda_cliente_mensagens x
   where x.client_id = any (v_cli) and x.tipo = any (c_esperam)
     and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
           and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
          or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
              and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade))
   order by coalesce(x.enviada_em, x.enviar_em) desc, x.criada_em desc, x.id
   limit 1;
  -- CORREÇÃO FASE 5: (A1 = item 11) a resposta só é da agenda quando a última mensagem que a HBR mandou a esse número é a
  -- dela: o botão antigo (o pedido de 30/09) ou o dono (ou outra rotina) falando com o cliente depois dela = a resposta é
  -- dessa outra conversa — devolve consumiu false (abaixo) e os leitores de antes (o "sim" de 30/09, a revisão) seguem.
  if m.id is not null then
    v_outra := public._agenda_cliente_outra_conversa(v_cli, p_phone, coalesce(m.enviada_em, m.enviar_em), p_agora);
  end if;
  -- (item 2) o PARAR (e os outros opt-outs) vale SEMPRE para quem recebeu mensagem da agenda nos últimos c_opt_out_dias —
  -- fora da validade, depois de outra resposta, com o número de dois clientes ou depois de outra conversa: o pós-serviço
  -- promete "é só responder PARAR". Marca o opt-out de cada cliente do número que recebeu, cancela as vivas dele, grava a
  -- resposta (efeito opt_out) e a ação; nada responde ao cliente.
  if v_modo = 'ligado' and v_tipo = 'text' and p_intencao = 'opt_out' and not public._e_concordancia(p_body)
     and (m.id is null or v_outra or v_n > 1 or cardinality(v_cli) > 1) then
    select coalesce(array_agg(distinct x.client_id), '{}'::uuid[]) into v_opt_cli
      from public.agenda_cliente_mensagens x
     where x.client_id = any (v_cli) and x.modo = 'ligado' and x.enviada_em is not null
       and x.enviada_em <= p_agora and x.enviada_em > p_agora - c_opt_out_dias;
    if cardinality(v_opt_cli) > 0 then
      select x.id, x.service_order_id into v_opt_msg, v_opt_os
        from public.agenda_cliente_mensagens x
       where x.client_id = any (v_opt_cli) and x.modo = 'ligado' and x.enviada_em is not null and x.enviada_em <= p_agora
       order by x.enviada_em desc, x.id limit 1;
      insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                                   tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
      values (v_rid, v_opt_cli[1], v_opt_os, v_opt_msg, p_message_id, p_agora, v_tipo, v_trecho, 'opt_out', null, null,
              'opt_out', 'ligado')
      on conflict (whatsapp_message_id) do nothing;
      if not found then
        return jsonb_build_object('consumiu', true, 'repetida', true);
      end if;
      foreach v_c in array v_opt_cli loop
        update public.clients set opt_out_whatsapp = true where id = v_c and not coalesce(opt_out_whatsapp, false);
        for v_id in select x.id from public.agenda_cliente_mensagens x
                     where x.client_id = v_c and x.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                     order by x.enviar_em, x.id loop
          if public._agenda_cliente_cancelar(v_id, 'opt_out', 'O cliente pediu para não receber mensagens.') then
            v_k := v_k + 1;
          end if;
        end loop;
      end loop;
      v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                            from public.clients cl where cl.id = v_opt_cli[1]), 'cliente');
      v_texto := format('O %s pediu para não receber mais mensagens: não mando mais nada a ele.', v_nome);
      -- FASE 6: (P7) a ação do opt-out sem artigo antes do nome e sem "a ele" (spec-fase6 §6.4)
      v_texto := format('%s pediu para não receber mais mensagens: não mando mais nada.', v_nome);
      -- FASE 6: fim
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, motivo)
      values (clock_timestamp(), v_hoje, true, 'cliente', 'cliente', v_opt_os, array[v_opt_os], '{}'::jsonb,
              jsonb_build_object('efeito', 'opt_out', 'resposta_id', v_rid, 'mensagem_id', v_opt_msg, 'canceladas', v_k,
                                 'clientes', to_jsonb(v_opt_cli), 'fora_da_mensagem', true),
              v_texto, 'o cliente pediu para parar')
      returning id into v_acao;
      update public.agenda_cliente_respostas set acao_id = v_acao where id = v_rid;
      return jsonb_build_object('consumiu', true, 'modo', 'ligado', 'efeito', 'opt_out', 'intencao', 'opt_out', 'texto', v_texto,
                                'resposta_id', v_rid, 'mensagem_id', v_opt_msg, 'acao_id', v_acao, 'pergunta_id', null);
    end if;
  end if;
  -- CORREÇÃO FASE 5: fim
  if m.id is null then
    return jsonb_build_object('consumiu', false, 'motivo', 'sem_mensagem');
  end if;
  -- CORREÇÃO FASE 5: (A1) a outra conversa depois da mensagem da agenda: não é resposta a ela (em teste também: a sombra
  -- não registra o que a agenda não leria)
  if v_outra then
    return jsonb_build_object('consumiu', false, 'modo', v_modo, 'motivo', 'outra_conversa', 'mensagem_id', m.id);
  end if;
  -- CORREÇÃO FASE 5: fim

  -- a intenção: o áudio e a mídia antes de tudo (nunca confirmam); o SIM curto pela regra única de 30/09; o resto como o
  -- leitor do webhook classificou (sem IA)
  v_int := case when v_tipo = 'audio' then 'audio'
                when v_tipo <> 'text' then 'outro'
                when public._e_concordancia(p_body) then 'confirma'
                when p_intencao in ('remarcar', 'falta', 'data', 'acesso', 'opt_out', 'disputa', 'negociacao', 'pergunta',
                                    'acordo', 'outro') then p_intencao
                else 'outro' end;
  -- FASE 7d: (correção R3) o "sim" atrasado do M1: com o M11 mais novo e a confirmação do dia da mesma OS pendente, o SIM é do dia, não do onde fica. A régua de quem espera é a de cima
  if m.tipo = 'onde_fica' and v_int = 'confirma' then
    select x.* into v_7d_m1
      from public.agenda_cliente_mensagens x
     where x.service_order_id = m.service_order_id and x.id <> m.id
       and (x.tipo in ('confirmar', 'material_chegou', 'nova_data', 'mudanca_no_dia') or (x.tipo = 'pode_atrasar' and x.variante = 'remarcado'))
       and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
             and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
            or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
                and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade))
     order by coalesce(x.enviada_em, x.enviar_em) desc, x.criada_em desc, x.id
     limit 1;
    if v_7d_m1.id is not null then
      m := v_7d_m1;
    end if;
  end if;
  -- FASE 7d: fim
  v_expr := case when v_int in ('data', 'remarcar', 'falta') then nullif(left(btrim(coalesce(p_expressao, '')), 60), '') end;
  v_dia := coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo);
  v_data := case when v_expr is not null then public._agenda_cliente_data_da_resposta(v_expr, v_hoje, v_dia) end;
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.clients cl where cl.id = m.client_id), 'cliente');
  v_ref := public._agenda_cliente_a_mensagem(m.tipo, m.variante, v_dia);
  v_do_dia := m.tipo = any (c_do_dia) or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado');

  -- em teste: só registra o que faria (a intenção); nada muda e os fluxos de hoje seguem iguais
  if v_modo = 'sombra' then
    insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                                 tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
    values (v_rid, m.client_id, m.service_order_id, m.id, p_message_id, p_agora, v_tipo, v_trecho, v_int, v_expr,
            (v_data ->> 'de')::date, 'sombra', 'sombra')
    on conflict (whatsapp_message_id) do nothing;
    return jsonb_build_object('consumiu', false, 'modo', 'sombra', 'efeito', 'sombra', 'intencao', v_int, 'resposta_id', v_rid);
  end if;

  -- ligado: a resposta fica registrada primeiro (uma por mensagem do WhatsApp); o efeito vem depois
  insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                               tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
  values (v_rid, m.client_id, m.service_order_id, case when v_n > 1 or cardinality(v_cli) > 1 then null else m.id end,
          p_message_id, p_agora, v_tipo, v_trecho, v_int, v_expr, (v_data ->> 'de')::date, 'nada', 'ligado')
  on conflict (whatsapp_message_id) do nothing;
  if not found then
    return jsonb_build_object('consumiu', true, 'repetida', true);
  end if;
  perform set_config('agenda.hoje', v_hoje::text, true);

  begin
    if v_n > 1 or cardinality(v_cli) > 1 then
      -- duas OS (ou dois clientes no número) esperando: não adivinha
      v_efeito := 'ambigua';
      v_texto := format('Chegou "%s" do número do %s, mas %s: não sei a qual mensagem é. Não respondi nada; é com você.',
                        public._agenda_corta(coalesce(v_trecho, 'uma mensagem que não é texto'), 120), v_nome,
                        case when cardinality(v_cli) > 1 then format('o número é de %s clientes', cardinality(v_cli))
                             else format('há %s serviços esperando resposta dele', v_n) end);
      -- FASE 6: (P7) sem artigo antes do nome e sem "dele" (spec-fase6 §6.4), escrito já assim: com dois clientes no número, a
      -- OS da mensagem pode ser do outro, e o ralo (que troca só o 1º nome do cliente da OS) não acharia este
      v_texto := format('Chegou "%s" do número de %s, mas %s: não sei a qual mensagem é. Não respondi nada; é com você.',
                        public._agenda_corta(coalesce(v_trecho, 'uma mensagem que não é texto'), 120), v_nome,
                        case when cardinality(v_cli) > 1 then format('o número é de %s clientes', cardinality(v_cli))
                             else format('há %s serviços esperando resposta do cliente', v_n) end);
      -- FASE 6: fim
    elsif v_int = 'audio' then
      -- o áudio NUNCA confirma: vai ao dono
      v_efeito := 'ao_dono';
      v_texto := format('O %s respondeu por áudio %s; a transcrição está na conversa. Não respondi nada; é com você.', v_nome, v_ref);
    elsif v_tipo <> 'text' then
      v_efeito := 'ao_dono';
      v_texto := format('O %s respondeu com %s %s. Não respondi nada; é com você.', v_nome,
                        case v_tipo when 'image' then 'uma foto' when 'video' then 'um vídeo' when 'document' then 'um documento'
                                    else 'uma mensagem que não é texto' end, v_ref);
    -- FASE 7d: (7d P6; §5.6, R6.3-5) a resposta ao M11: anota, pergunta ao dono e NÃO conta como acesso combinado. O áudio e a mídia já foram ao dono, acima;
    -- o PARAR, a reclamação e a negociação seguem o caminho de sempre, abaixo.
    -- (correção R3, R4) o acordo entra no mesmo leitor do texto inteiro ("Sim, na Marina Itajaí"). Sem sinal de lugar, _agenda_cliente_anotar_onde não anota nada: a resposta vai ao dono como
    -- resposta comum. O acordo e a pergunta sem lugar seguem os textos de sempre, abaixo.
    elsif m.tipo = 'onde_fica' and v_int not in ('opt_out', 'disputa', 'negociacao')
          and (v_int not in ('acordo', 'pergunta')
               or coalesce((public._agenda_local_proposto(m.service_order_id, v_trecho, v_hoje) ->> 'sinal')::boolean, false)) then
      v_x := public._agenda_cliente_anotar_onde(m.id, v_rid, v_trecho, v_hoje, p_agora);
      if coalesce((v_x ->> 'ok')::boolean, false) then
        v_efeito := 'anotou_acesso';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_perg := (v_x ->> 'pergunta_id')::uuid;
        v_texto := v_x ->> 'texto';
      else
        v_efeito := 'ao_dono';
        v_o_que := v_x ->> 'o_que';
        v_texto := v_x ->> 'texto';
      end if;
    -- FASE 7d: fim
    elsif v_int = 'confirma' then
      if m.tipo in ('confirmar', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado') then
        -- (decisão do P4) o SIM ao aviso remarcado confirma o dia novo, como o M1: o texto dele pede "Responda SIM"
        v_x := public._agenda_cliente_confirmar_dia(m.id, v_rid, v_trecho, v_hoje, p_agora);
        if coalesce((v_x ->> 'ok')::boolean, false) then
          v_efeito := 'confirmou';
          v_acao := (v_x ->> 'acao_id')::uuid;
          v_texto := v_x ->> 'texto';
        else
          v_efeito := 'ao_dono';
          v_o_que := v_x ->> 'o_que';
        end if;
      elsif m.tipo in ('vespera', 'acesso') then
        v_efeito := 'confirmou';   -- só registra (o client_confirmed_* é do SIM ao M1/M3/M7/M10)
      elsif m.tipo = 'pode_atrasar' then
        v_efeito := 'ciencia';
      elsif m.tipo in ('pronto', 'pronto_lembrete') then
        v_efeito := 'ao_dono';
        v_o_que := 'combine a entrega com ele';
      else
        v_efeito := 'nada';
      end if;
    elsif v_int = 'opt_out' then
      -- honrado calado (d8): nada mais sai a ele; o dono fica sabendo pela ação
      update public.clients set opt_out_whatsapp = true where id = m.client_id and not coalesce(opt_out_whatsapp, false);
      for v_id in select x.id from public.agenda_cliente_mensagens x
                   where x.client_id = m.client_id and x.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                   order by x.enviar_em, x.id loop
        if public._agenda_cliente_cancelar(v_id, 'opt_out', 'O cliente pediu para não receber mensagens.') then
          v_k := v_k + 1;
        end if;
      end loop;
      v_efeito := 'opt_out';
      v_texto := format('O %s pediu para não receber mais mensagens: não mando mais nada a ele.', v_nome);
      -- FASE 6: (P7) a ação do opt-out sem artigo antes do nome e sem "a ele" (spec-fase6 §6.4)
      v_texto := format('%s pediu para não receber mais mensagens: não mando mais nada.', v_nome);
      -- FASE 6: fim
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, motivo)
      values (clock_timestamp(), v_hoje, true, 'cliente', 'cliente', m.service_order_id, array[m.service_order_id], '{}'::jsonb,
              jsonb_build_object('efeito', 'opt_out', 'resposta_id', v_rid, 'mensagem_id', m.id, 'canceladas', v_k),
              v_texto, 'o cliente pediu para parar')
      returning id into v_acao;
    elsif v_int in ('disputa', 'negociacao', 'acordo', 'pergunta') then
      v_efeito := 'ao_dono';
      v_acorde := v_int = 'disputa';   -- a reclamação vai na hora
      v_o_que := case v_int when 'disputa' then 'parece reclamação'
                            when 'negociacao' then 'é sobre preço ou pagamento'
                            when 'acordo' then 'parece que concorda, mas não é um SIM claro'
                            else 'é uma pergunta' end;
    elsif v_int in ('data', 'remarcar', 'falta') and not v_do_dia then
      v_efeito := 'ao_dono';
      v_o_que := case when m.tipo in ('pronto', 'pronto_lembrete') then 'falou de dia: combine a entrega com ele'
                      else 'falou de outro dia' end;
    elsif v_int in ('data', 'remarcar', 'falta') and cf.modo_proposta <> 'ligado' then
      v_efeito := 'ao_dono';
      v_o_que := 'pediu outro dia, mas a agenda automática não está ligada: remarque você';
    elsif v_int = 'data' then
      v_de := (v_data ->> 'de')::date;
      v_ate := (v_data ->> 'ate')::date;
      if v_de is null then
        v_efeito := 'ao_dono';
        v_o_que := 'não entendi o dia que ele pediu';
      elsif v_de <= v_hoje then
        v_efeito := 'ao_dono';
        v_o_que := 'o dia que ele pediu já passou ou é hoje';
      elsif v_dia is not null and v_de = v_dia then
        v_efeito := 'ao_dono';
        v_o_que := 'falou do mesmo dia combinado';
      elsif v_dia is not null and v_de < v_dia then
        -- (decisão do P4) mais cedo que o combinado: o "não antes de" não adianta nada; é o dono que vê se dá
        v_efeito := 'ao_dono';
        v_o_que := format('pediu um dia antes do combinado (%s)', public._dia_curto(v_de));
      -- CORREÇÃO FASE 5: (item 9) o dia pedido longe demais do combinado (mais de cliente_pedido_max_du dias úteis) não
      -- remarca sozinho: é o dono que vê
      elsif public.agenda_du_entre(coalesce(v_dia, v_hoje), v_de) > cf.cliente_pedido_max_du then
        v_efeito := 'ao_dono';
        v_o_que := format('pediu %s, mais de %s dias úteis depois do combinado: remarque você', public._dia_curto(v_de),
                          cf.cliente_pedido_max_du);
      -- CORREÇÃO FASE 5: fim
      else
        v_x := public._agenda_cliente_pedido_de_dia(m.id, v_rid,
                 case when v_dia is not null then daterange(v_dia, v_dia, '[]') end, v_de,
                 format('O %s pediu %s', v_nome,
                        case when v_ate > v_de then 'a partir de ' || public._dia_curto(v_de) else public._dia_curto(v_de) end),
                 v_trecho, v_hoje, p_agora);
        v_efeito := 'replanejou';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_texto := v_x ->> 'texto';
      end if;
    -- CORREÇÃO FASE 5: (item 17) falta/remarcar com um número de dia que o banco não entendeu ("tô viajando, volto dia 20",
    -- "só depois de 20/11"): tirar só o dia combinado remarcaria para quando ele ainda está fora — vai ao dono
    elsif v_int in ('remarcar', 'falta') and v_data is null
          and public._agenda_preparar_data(coalesce(v_trecho, '')) ~ '(\mdia \d{1,2}\M|\m\d{1,2}/\d{1,2})' then
      v_efeito := 'ao_dono';
      v_o_que := 'falou de outro dia, que eu não entendi';
    -- CORREÇÃO FASE 5: fim
    elsif v_int in ('remarcar', 'falta') then
      -- o dia recusado: o que ele disse (convertido pelo banco), senão o dia da mensagem
      v_de := (v_data ->> 'de')::date;
      v_ate := (v_data ->> 'ate')::date;
      if v_de is null or v_ate < v_hoje then
        v_de := v_dia;
        v_ate := v_dia;
      end if;
      v_de := greatest(v_de, v_hoje);
      if v_de is null or v_ate < v_de then
        v_efeito := 'ao_dono';
        v_o_que := 'pediu outro dia';
      elsif not (v_dia between v_de and v_ate)
            and not exists (select 1 from public.agenda_alocacoes a
                             where a.service_order_id = m.service_order_id and a.estado in ('publicada', 'fixada')
                               and a.tipo <> 'reserva' and a.dia between v_de and v_ate) then
        -- (decisão do P4) o dia recusado não é dia do serviço ("não dá amanhã" no sábado, com o serviço na terça): não
        -- adivinho de qual dia ele fala
        v_efeito := 'ao_dono';
        v_o_que := format('disse que não dá %s, mas não é dia do serviço',
                          case when v_ate > v_de then public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate)
                               else public._dia_curto(v_de) end);
      -- CORREÇÃO FASE 5: (item 9) tirar dias até longe demais do combinado ("vou viajar até 20/12") também não remarca sozinho
      elsif public.agenda_du_entre(coalesce(v_dia, v_hoje), v_ate) > cf.cliente_pedido_max_du then
        v_efeito := 'ao_dono';
        v_o_que := format('disse que não dá até %s, mais de %s dias úteis depois do combinado: remarque você',
                          public._dia_curto(v_ate), cf.cliente_pedido_max_du);
      -- CORREÇÃO FASE 5: fim
      else
        v_x := public._agenda_cliente_pedido_de_dia(m.id, v_rid, daterange(v_de, v_ate, '[]'), null,
                 format('O %s pediu outro dia (%s não dá)', v_nome,
                        case when v_ate > v_de then public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate)
                             else public._dia_curto(v_de) end),
                 v_trecho, v_hoje, p_agora);
        v_efeito := 'replanejou';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_texto := v_x ->> 'texto';
      end if;
    -- CORREÇÃO FASE 5: (item 16) o acesso com negação ("não sei onde vai estar a chave", "não tenho a chave", "ainda não
    -- sei") não é acesso dito: não vai para o campo da OS nem desliga a pergunta do acesso — vai ao dono
    elsif v_int = 'acesso' and public._agenda_normal(coalesce(v_trecho, '')) ~ '\m(nao sei|nao tenho|ainda nao)\M' then
      v_efeito := 'ao_dono';
      v_o_que := 'falou do acesso, mas ainda não sabe (ou não tem) a chave';
    -- CORREÇÃO FASE 5: fim
    elsif v_int = 'acesso' and (v_do_dia or m.tipo = 'pode_atrasar') then
      v_x := public._agenda_cliente_anotar_acesso(m.id, v_rid, v_trecho, v_hoje, p_agora);
      v_efeito := 'anotou_acesso';
      v_acao := (v_x ->> 'acao_id')::uuid;
      v_texto := v_x ->> 'texto';
    else
      v_efeito := 'ao_dono';
      v_o_que := case when v_int = 'acesso' then 'falou do acesso' else 'não entendi o que ele quer' end;
    end if;
  exception when others then
    -- o efeito que falha não derruba o webhook: a resposta vai ao dono e o erro fica consultável
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    perform public.log_app_error('db', 'agenda: a resposta do cliente falhou: ' || v_msg, 'agenda', 'cliente:resposta', 'error',
                                 jsonb_build_object('mensagem', m.id, 'resposta', v_rid, 'intencao', v_int, 'sqlstate', v_estado));
    v_efeito := 'ao_dono';
    v_acao := null;
    v_acorde := false;
    v_o_que := 'não consegui ler a resposta sozinho';
    v_texto := null;
  end;

  -- ao dono: a pergunta cliente_resposta (sem opções; some em 7 dias), e o acorde na hora quando é reclamação
  if v_efeito in ('ao_dono', 'ambigua') then
    v_texto := coalesce(v_texto, format('O %s respondeu "%s" %s: %s. Não respondi nada; é com você.', v_nome,
                                        public._agenda_corta(coalesce(v_trecho, ''), 120), v_ref, v_o_que));
    v_perg := public._agenda_cliente_perguntar('cliente_resposta', 'cliente_resposta:' || v_rid, m.service_order_id, v_dia,
                                               case when v_do_dia then v_dia end, v_texto, 'ligado', p_agora,
                                               p_agora + c_pergunta_dias);
    if v_acorde then
      v_acao := public._agenda_cliente_acorde(m.service_order_id, 'cliente_resposta:' || v_rid, v_texto, v_hoje, v_hoje, v_perg);
    end if;
  end if;

  -- a mensagem respondida (antes das 48 h o "não respondeu" não a pega; depois, a pergunta dele se resolve)
  if v_efeito <> 'ambigua' then
    update public.agenda_cliente_mensagens set estado = 'respondida', resposta_id = v_rid
     where id = m.id and estado in ('enviada', 'sem_resposta');
    -- FASE 6: (P7) o motivo sem artigo antes do nome; o update de antes, logo abaixo, não acha mais a pergunta aberta
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(format('%s respondeu.', v_nome), 200)
     where chave = 'cliente_resposta:sem_resposta:' || m.id and estado = 'aberta';
    -- FASE 6: fim
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(format('O %s respondeu.', v_nome), 200)
     where chave = 'cliente_resposta:sem_resposta:' || m.id and estado = 'aberta';
  end if;
  update public.agenda_cliente_respostas
     set efeito = v_efeito, acao_id = v_acao, pergunta_id = v_perg, data_dita = coalesce((v_data ->> 'de')::date, data_dita)
   where id = v_rid;
  -- CORREÇÃO FASE 5: (item 15) o texto devolvido, quando é o da pergunta ao dono, sem artigo antes do nome ("Flávio
  -- respondeu …"), igual à pergunta; o das ações (confirmou, pediu, opt-out) fica como a ação gravada
  if v_efeito in ('ao_dono', 'ambigua') then
    v_texto := public._agenda_cliente_sem_artigo(v_texto, m.service_order_id);
  end if;
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('consumiu', true, 'modo', 'ligado', 'efeito', v_efeito, 'intencao', v_int, 'texto', v_texto,
                            'resposta_id', v_rid, 'mensagem_id', m.id, 'acao_id', v_acao, 'pergunta_id', v_perg);
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
  v_tok     text[] := public._agenda_local_palavras(p_ref);
  v_toks    text := array_to_string(public._agenda_local_palavras(p_ref), ' ');
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
           || case when x.tipo = 'patio_hbr' then c_patio else '{}'::text[] end as palavras
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
           array(select k from unnest(v_tok) k
                  where exists (select 1 from unnest(t.palavras) w where w = k or (char_length(k) >= c_prefixo and w like k || '%'))) as dele
      from t
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'municipio', c.municipio, 'so_cidade', v_toks = c.cidade,
                                               'tudo', cardinality(c.resto) > 0 and c.cobre = cardinality(c.resto),
                                               'exato', cardinality(c.resto) > 0 and c.exatas = cardinality(c.resto),
                                               'parte', cardinality(c.dele) > 0) order by c.ordem, c.id), '[]'::jsonb),
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

create or replace function public._agenda_planejar_linhas(p_d jsonb)
 returns text[]
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v     text[] := '{}';
  v_bem text := coalesce(nullif(p_d ->> 'bem_nome', ''), 'o barco');
  v_ent date := (p_d ->> 'entrada_em')::date;
  v_sai date := (p_d ->> 'retirada_em')::date;
begin
  if p_d ? 'local_id' then
    -- (correção O2, O3) antes do local_id: depois do *grava* a casa também tem local_id. O lugar novo só existe até o *grava*
    v := v || case when coalesce((p_d ->> 'local_casa')::boolean, false) then 'Local: na casa do cliente (anotei).'
                   when p_d ->> 'local_novo' is not null then format('Local: %s (lugar novo: entra no cadastro quando você gravar).', p_d ->> 'local_novo')
                   when p_d ->> 'local_id' is not null then format('Local: %s.', p_d ->> 'local_nome')
                   else 'Tirei o local que eu tinha (volto a supor).' end;
  end if;
  if p_d ->> 'bem_situacao' is not null then
    v := v || format('%s: %s.', public._agenda_maiuscula(v_bem),
                     case p_d ->> 'bem_situacao' when 'agua' then 'na água' when 'seco' then 'em seco' when 'garagem_seca' then 'em seco (garagem)'
                                                 when 'patio' then 'no pátio' else 'com o cliente' end);
  end if;
  if p_d ->> 'descer_quem' is not null then
    v := v || format('Quem desce: %s.', p_d ->> 'descer_quem');
  end if;
  if p_d ->> 'bem_exige' is not null then
    v := v || case p_d ->> 'bem_exige' when 'agua' then 'O teste final é na água.'
                                       when 'seco' then format('O serviço é com %s em seco.', v_bem)
                                       else 'Tanto faz na água ou em seco.' end;
  end if;
  if v_ent is not null and v_sai is not null then
    v := v || format('%s chega %s e sai %s.', public._agenda_maiuscula(v_bem), public._dia_curto(v_ent), public._dia_curto(v_sai));
  elsif v_ent is not null then
    v := v || format('%s chega %s.', public._agenda_maiuscula(v_bem), public._dia_curto(v_ent));
  elsif v_sai is not null then
    v := v || format('%s sai %s.', public._agenda_maiuscula(v_bem), public._dia_curto(v_sai));
  end if;
  if p_d ? 'viagem' then
    v := v || case p_d ->> 'viagem' when 'regional' then 'Sem viagem (aqui na região).'
                                    when 'bate_volta' then 'Viagem: ida e volta no mesmo dia.'
                                    when 'pernoite' then 'Viagem com pernoite: a equipe vai e volta junta, em dias seguidos.'
                                    else 'Tirei a viagem que eu tinha (volto a supor).' end;
  end if;
  if jsonb_array_length(coalesce(p_d -> 'autorizados', '[]'::jsonb)) > 0 then
    v := v || format('Autorizados nesse serviço: %s.', public._agenda_lista(array(
                select case when (e ->> 'eh_dono')::boolean then 'você' else e ->> 'nome' end
                  from jsonb_array_elements(p_d -> 'autorizados') with ordinality t(e, o) order by o), null));
  end if;
  -- O que limpou
  if p_d ? 'entrada_em' and v_ent is null then
    v := v || 'Tirei a data de chegada.'::text;
  end if;
  if p_d ? 'retirada_em' and v_sai is null then
    v := v || 'Tirei a data de saída.'::text;
  end if;
  if p_d ? 'autorizados' and jsonb_array_length(p_d -> 'autorizados') = 0 then
    v := v || 'Tirei a lista de autorizados.'::text;
  end if;
  return v;
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
  v_7d_limpar text[] := '{}';
  v_7d_rl    jsonb;
  v_7d_txt   text;
  v_7d_aut   jsonb := '[]'::jsonb;
  v_7d_velho jsonb;
  v_7d_ent   date;
  v_7d_sai   date;
  v_7d_novo  jsonb;   -- (correção O2) o lugar novo
  v_7d_mun   jsonb;   -- (correção O2) a cidade dele, se é conhecida
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
    v_7d_rl := public.agenda_resolver_local(d ->> 'local', p_hoje);
    if v_7d_rl ->> 'status' = 'casa_cliente' then
      v_out := v_out || jsonb_build_object('local_id', null, 'local_nome', null, 'local_casa', true, 'local_novo', null);
    elsif v_7d_rl ->> 'status' = 'ok' then
      v_out := v_out || jsonb_build_object('local_id', v_7d_rl ->> 'id', 'local_nome', v_7d_rl ->> 'nome', 'local_casa', false, 'local_novo', null);
    -- (correção O2) o lugar fora do cadastro: se o texto é um nome plausível, entra; o *grava* cria a linha (só o dono passa por aqui: o M11 só pergunta). A cidade só se é conhecida
    elsif v_7d_rl ->> 'status' = 'nao_achei' then
      v_7d_novo := public._agenda_local_novo(d ->> 'local');
      if not (v_7d_novo ->> 'ok')::boolean then
        return public._agenda_recusa(v_7d_novo ->> 'texto', 'local_' || (v_7d_novo ->> 'motivo'));
      end if;
      v_7d_mun := public._agenda_municipio_conhecido(v_7d_novo ->> 'nome', v_os);
      v_out := v_out || jsonb_build_object('local_id', null, 'local_nome', v_7d_novo ->> 'nome', 'local_casa', false, 'local_novo', v_7d_novo ->> 'nome',
                                           'local_municipio', v_7d_mun ->> 'municipio', 'local_uf', v_7d_mun ->> 'uf');
    else
      return public._agenda_recusa(v_7d_rl ->> 'texto', 'local_' || (v_7d_rl ->> 'status'),
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
    if public._agenda_data_sem_mes(d ->> 'chega_em') and (v_dt ->> 'de')::date > p_hoje
       and public._agenda_normal(p_trecho) ~ '\m(chegou|entrou|veio|trouxe|deixou|ja esta)\M' then
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
    if (v_dt ->> 'de')::date = p_hoje and (v_dt ->> 'ate')::date > p_hoje then
      return public._agenda_recusa('Que dia sai? Diga um dia só (por exemplo, "dia 13").', 'data_faixa');
    end if;
    v_out := v_out || jsonb_build_object('retirada_em', v_dt ->> 'de');
    -- (correção O7b) a chegada sem mês depois da saída dita na mesma frase: "chega dia 5 e ele busca dia 13", dito em 06/11, é 05/11 e 13/11. A chegada cai no mês da saída ou no anterior,
    -- se assim ficar antes dela. A releitura mostra as 2 datas por extenso antes do *grava*.
    if d ? 'chega_em' and public._agenda_data_sem_mes(d ->> 'chega_em')
       and (v_out ->> 'entrada_em')::date >= (v_out ->> 'retirada_em')::date then
      v_7d_ent := public._agenda_data_um(public._agenda_preparar_data(d ->> 'chega_em'), p_hoje, 'futuro', true, (v_out ->> 'retirada_em')::date - 1, null);
      if v_7d_ent is not null and v_7d_ent < (v_out ->> 'retirada_em')::date then
        v_out := v_out || jsonb_build_object('entrada_em', v_7d_ent);
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
                                                          'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false)));
    end loop;
    v_out := v_out || jsonb_build_object('autorizados', v_7d_aut);
  end if;
  if 'local' = any (v_7d_limpar) then
    v_out := v_out || jsonb_build_object('local_id', null, 'local_nome', null, 'local_casa', false, 'local_novo', null);
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

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'planejar', 'planejar:' || v_os::text, v_os,
                                          public._agenda_os_do_rascunho(v_ro) || jsonb_build_object('bem_nome', v_bem) || v_out,
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
    end if;
    if d ? 'local_id' then
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
      v_7d_dep := v_7d_dep || jsonb_build_object('local_id', v_new.local_id, 'local_fonte', v_new.local_fonte, 'local_em', v_new.local_em);
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

create or replace function public._agenda_desfazer_local(p_acao uuid, p_autor uuid, p_via text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  a       public.agenda_acoes%rowtype;
  v_os    uuid;
  v_ef    text;
  v_nome  text;
  v_id    uuid;
  v_r     jsonb;
  v_txts  text[] := '{}';
  v_falha text;
  v_txt   text;
  v_acao  uuid;
begin
  select * into a from public.agenda_acoes where id = p_acao;
  v_os := a.service_order_id;
  v_ef := a.depois ->> 'efeito';
  v_nome := coalesce(a.depois #>> '{item,cliente}', public._agenda_rotulo_da_os(v_os), 'serviço');
  if a.desfazivel_ate is null or p_agora > a.desfazivel_ate then
    return jsonb_build_object('ok', false, 'texto', format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga.', v_nome));
  end if;
  if not public._agenda_local_restaurar(a.id, p_autor, p_agora) then
    return jsonb_build_object('ok', false, 'texto', format('Não desfaço: depois disso o plano do %s mudou. Se quiser mudar, me diga.', v_nome));
  end if;
  update public.os_autorizados x set revogado_em = p_agora
   where x.service_order_id = v_os and x.revogado_em is null
     and x.payee_id in (select y::uuid from jsonb_array_elements_text(coalesce(a.depois -> 'autorizados', '[]'::jsonb)) y);

  -- FASE 7d: (7d P7, §5.7) o que o *grava* do os_planejar fez fora das colunas: as linhas de os_autorizados voltam como estavam (quem saiu da lista volta; quem já estava fica) e a
  -- pergunta que ele fechou volta a esperar, se ainda vale: fechada não muda, então é outra linha, com o mesmo texto e as mesmas opções
  update public.os_autorizados x
     set local_id = (e.l ->> 'local_id')::uuid, valido_ate = (e.l ->> 'valido_ate')::date, fonte = e.l ->> 'fonte', trecho = e.l ->> 'trecho',
         revogado_em = (e.l ->> 'revogado_em')::timestamptz, criado_em = (e.l ->> 'criado_em')::timestamptz, criado_por = (e.l ->> 'criado_por')::uuid
    from jsonb_array_elements(coalesce(a.antes -> 'autorizados_linhas', '[]'::jsonb)) e(l)
   where x.service_order_id = v_os and x.payee_id = (e.l ->> 'payee_id')::uuid;
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao, versao_base, modo, criada_em, expira_em)
  select q.tipo, q.chave, q.service_order_id, q.os_ids, q.dia, q.perda_em, q.texto, q.opcoes, q.recomendacao, q.versao_base, q.modo, p_agora, q.expira_em
    from public.agenda_perguntas q
   where q.id in (select y::uuid from jsonb_array_elements_text(coalesce(a.depois -> 'perguntas_fechadas', '[]'::jsonb)) y)
     and (q.expira_em is null or q.expira_em > p_agora)
  on conflict (chave, modo) where estado = 'aberta' do nothing;
  -- (correção O2, O3) a linha que o dono criou pela conversa some se nenhuma OS a usa: nunca se apaga (sai por ativo), e o próximo *grava* do mesmo lugar a reativa. Local conferido fica
  if a.depois ->> 'local_id' is not null then
    update public.agenda_locais l set ativo = false, atualizado_por = p_autor
     where l.id = (a.depois ->> 'local_id')::uuid and l.ativo and l.tipo in ('outro', 'casa_cliente') and l.conferido_por is null
       and not exists (select 1 from public.os_planejamento p where p.local_id = l.id)
       and not exists (select 1 from public.os_autorizados x where x.local_id = l.id and x.revogado_em is null);
  end if;
  -- FASE 7d: fim
  -- O replano do "Segure o dia" volta junto (cada ação dele, pelo desfazer de sempre)
  perform set_config('agenda.desfazer_local', 'on', true);
  for v_id in select x::uuid from jsonb_array_elements_text(coalesce(a.depois -> 'replano_acoes', '[]'::jsonb)) x loop
    if exists (select 1 from public.agenda_acoes e where e.id = v_id and e.executada and e.desfeita_em is null) then
      v_r := public.agenda_desfazer(v_id, p_autor, p_via, p_hoje, p_agora);
      if coalesce((v_r ->> 'ok')::boolean, false) then
        v_txts := v_txts || (v_r ->> 'texto');
      else
        v_falha := v_r ->> 'texto';
      end if;
    end if;
  end loop;
  perform set_config('agenda.desfazer_local', '', true);

  if v_ef = 'local' then
    v_txt := format('Desfeito: o local do serviço de %s voltou a ser o que eu supunha.', v_nome);
  -- FASE 7d: (7d P7, §6.3) só o local suposto ou só quem entrou na lista: os textos da §6.3; o resto, a frase de uma linha
  elsif v_ef = 'planejar' then
    v_txt := case when (a.antes - 'trecho' - 'local_id' - 'local_fonte' - 'local_em') = '{}'::jsonb and a.antes ? 'local_id' and a.antes ->> 'local_id' is null
                    then format('Desfeito: o local do serviço de %s voltou a ser o que eu supunha.', v_nome)
                  when (a.antes - 'trecho' - 'autorizados_linhas') = '{}'::jsonb and jsonb_array_length(coalesce(a.depois -> 'autorizados', '[]'::jsonb)) > 0
                    then public._agenda_combinar_texto(jsonb_build_object('tipo', 'acesso', 'nominal', true, 'nomes', (
                           select jsonb_agg(public._agenda_nome_curto(py.name) order by py.name)
                             from public.payees py
                            where py.id in (select y::uuid from jsonb_array_elements_text(a.depois -> 'autorizados') y))), 'desfeito', p_hoje)
                  else format('Desfeito: o serviço de %s voltou como estava.', v_nome) end;
  -- FASE 7d: fim
  elsif v_ef = 'segurar' then
    v_txt := case when cardinality(v_txts) > 0 then array_to_string(v_txts, ' ')
                  else format('Desfeito: não seguro mais o dia do %s.', v_nome) end || coalesce(' ' || v_falha, '');
  else
    v_txt := public._agenda_combinar_texto(a.depois -> 'item', 'desfeito', p_hoje);
  end if;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os, a.os_ids, false,
          jsonb_build_object('acao', a.id), a.antes, public._agenda_corta(v_txt, 400), p_autor, a.id)
  returning id into v_acao;
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = a.id;
  return jsonb_build_object('ok', true, 'texto', public._agenda_corta(v_txt, 400), 'acao_id', v_acao, 'recriadas', '[]'::jsonb, 'canceladas', '[]'::jsonb);
end;
$function$;

create or replace function public._agenda_local_bloco(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_mc    text := public._agenda_local_modo('calendario');
  v_ma    text := public._agenda_local_modo('acesso');
  v_mb    text := public._agenda_local_modo('bem');
  v_mp    text := public._agenda_local_modo('patio');
  v_mv    text := public._agenda_local_modo('viagem');
  v_ml    text := public._agenda_local_modo('mesmo_local');
  v_modos text[];
  v_lr    jsonb;
  v_vi    jsonb;
  v_vtxt  text;
  v_bem   jsonb;
  v_au    jsonb;
  v_cmb   jsonb;
  v_perg  date;
  v_notas text[] := '{}';
  v_sup   text[] := '{}';
  v_vagas int;
begin
  v_modos := array[v_mc, v_ma, v_mb, v_mp, v_mv, v_ml];
  if 'sombra' <> all (v_modos) and 'ligado' <> all (v_modos) then
    return null;   -- os 6 desligados: nada disto existe para o dono (§3.2)
  end if;
  v_lr := public._agenda_local_resolvido(p_os, p_hoje);
  if v_lr is null then
    return null;
  end if;

  -- O barco cadastrado noutro lugar, ou a marina da OS fora do cadastro (NOVO-agenda-63)
  if nullif(v_lr ->> 'nota_bem', '') is not null then
    v_notas := v_notas || (public._agenda_maiuscula(v_lr ->> 'nota_bem') || '.');
  end if;

  if v_mv <> 'desligado' then
    v_vi := public._agenda_viagem_da_os(p_os, p_hoje, v_lr);
    if v_vi ->> 'tipo' <> 'regional' then
      v_vtxt := case when v_mv = 'sombra' then 'Em teste: ' || lower(left(v_vi ->> 'texto', 1)) || substr(v_vi ->> 'texto', 2) else v_vi ->> 'texto' end;
    end if;
  end if;

  if v_mb <> 'desligado' then
    v_bem := public._agenda_estado_do_bem(p_os, p_hoje);
    -- "supus o motorhome na MP Motorhomes" é o que o texto do local já diz
    v_sup := v_sup || array(select x from jsonb_array_elements_text(coalesce(v_bem -> 'suposicoes', '[]'::jsonb)) x where x !~ '^supus o (motorhome|barco|bem) n[ao] ');
  end if;

  if v_ma <> 'desligado' then
    v_au := public._agenda_autorizacao_da_os(p_os, p_hoje, v_lr);
    if jsonb_array_length(coalesce(v_au -> 'nomes', '[]'::jsonb)) > 0 then
      v_notas := v_notas || (v_au ->> 'texto');
    end if;
  end if;

  -- As regras que ainda são nota. Um dia só basta: as notas não dependem da janela.
  v_notas := v_notas || array(select x from jsonb_array_elements_text(coalesce(public._agenda_local_mascara(p_os, p_hoje, p_hoje, p_hoje, v_lr) -> 'notas', '[]'::jsonb)) x);

  -- O que o motor supôs na última montagem desta OS: as chaves só existem com os modos ligados (R6.8-3). A do local e a da viagem já estão no texto.
  if 'ligado' = any (v_modos) then
    v_sup := v_sup || array(
      select x
        from (select i -> 'suposicoes' as s
                from public.agenda_propostas pr
               cross join lateral jsonb_array_elements(coalesce(pr.itens, '[]'::jsonb)) i
               where i ->> 'os' = p_os::text and i ? 'suposicoes'
               order by pr.criada_em desc, pr.id desc limit 1) u
       cross join lateral jsonb_array_elements_text(u.s) x
       where x !~ '^supus o (motorhome|barco|bem) n[ao] ' and x !~ ': supus ' and x is distinct from v_lr ->> 'texto');
  end if;
  -- As suposições, como frase: a maiúscula e o ponto (no item da proposta elas vão em minúscula e sem ponto, §6.2)
  v_sup := array(select public._agenda_maiuscula(x) || case when right(x, 1) = '.' then '' else '.' end from unnest(v_sup) with ordinality u(x, o) order by u.o);
  v_notas := array(select y.x from (select u.x, min(u.o) as o from unnest(v_notas || v_sup) with ordinality u(x, o) group by u.x) y order by y.o);

  select coalesce(jsonb_agg(jsonb_build_object('texto', e ->> 'texto', 'ate', e ->> 'ate', 'vencido', (e ->> 'vencido')::boolean,
                                               'em_teste', e ->> 'modo' <> 'ligado') order by o), '[]'::jsonb)
    into v_cmb
    from jsonb_array_elements(public._agenda_combinar_da_os(p_os, p_hoje)) with ordinality t(e, o)
   where not (e ->> 'combinado')::boolean and e ->> 'modo' <> 'desligado'
     and (e ->> 'para')::date > p_hoje;   -- no dia, não há mais o que combinar (a régua de _agenda_local_combinar)

  -- "Perguntei" só com o M11 que saiu de verdade (a lição do plano falso; a nota do P3, item 7)
  if v_lr ->> 'fonte' not in ('dono', 'cliente') then
    select (coalesce(m.enviada_em, m.enviar_em) at time zone 'America/Sao_Paulo')::date into v_perg
      from public.agenda_cliente_mensagens m
     where m.service_order_id = p_os and m.tipo = 'onde_fica' and m.modo = 'ligado' and m.estado in ('enviada', 'respondida', 'sem_resposta')
     order by coalesce(m.enviada_em, m.enviar_em) desc limit 1;
  end if;

  if v_lr ->> 'local_id' is not null then
    select l.vagas into v_vagas from public.agenda_locais l where l.id = (v_lr ->> 'local_id')::uuid;
  end if;

  return jsonb_build_object(
    'texto', v_lr ->> 'texto', 'fonte', v_lr ->> 'fonte', 'suposicao', v_lr -> 'suposicao', 'tipo', v_lr ->> 'tipo', 'nome', v_lr ->> 'nome', 'vagas', v_vagas,
    'viagem_texto', v_vtxt, 'bem_texto', v_bem ->> 'texto',
    'perguntei', case when v_perg is not null then format('Perguntei ao cliente em %s.', to_char(v_perg, 'DD/MM')) end,
    'combinar', v_cmb, 'notas', to_jsonb(v_notas));
end;
$function$;

create or replace function public._agenda_ver_locais(p_hoje date, p_os uuid default null)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_semanas constant int := 3;    -- estrutural: as próximas 3 semanas (§6.2)
  c_linha   constant int := 400;  -- estrutural: o teto de cada linha (§6.2)
  c_nomes   constant int := 3;    -- estrutural: quantos locais a linha do cadastro cita (o resto: "e mais N")
  c_teste   constant int := 3;    -- estrutural: quantas linhas "Em teste" o texto mostra (em_teste leva todas)
  cf        public.agenda_config;
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_mc      text;
  v_ma      text;
  v_mp      text;
  v_mv      text;
  v_modos   text[];
  v_ate     date;
  r         record;
  e         jsonb;
  v_b       jsonb;
  v_rot     text;
  v_linha   text;
  v_lig     text[];
  v_tes     text[];
  v_n       text;
  v_nome    text;
  v_resto   text;
  v_lin     jsonb := '[]'::jsonb;
  v_l       text[] := '{}';
  v_fora    text[] := '{}';
  v_pat     text;
  v_pn      int := 0;
  v_pnome   text;
  v_total   int;
  v_dono    text[];
  v_mar     int;
  v_notas   text[];
  v_cad     text;
  v_cadj    jsonb;
  v_teste   text[] := '{}';
  v_rodape  text[];
  v_final   text[];
  v_cab     text;
  v_corte   int;
  -- FASE 7d: (correção O1, C9) o foco geral: todas as OS abertas, numa linha curta, as supostas primeiro; o que cortar quando passa do teto; a recomendação do apelido
  c_parar_dias  constant int := 28;   -- §11: 4 semanas
  c_parar_vezes constant int := 2;    -- §11: 2 gravações desfeitas do mesmo local
  v_lr      jsonb;
  v_lugar   text;
  v_por     text;
  v_sup     text[] := '{}';
  v_dit     text[] := '{}';
  v_nn      int;
  v_cd      int := 0;
  v_cs      int := 0;
  v_apelido text[] := '{}';
  -- FASE 7d: fim
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (o WhatsApp do dono).
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'Os locais dos serviços são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'Os locais dos serviços são com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_hoje is null then
    raise exception '_agenda_ver_locais: p_hoje é obrigatório.' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_mc := public._agenda_local_modo('calendario');
  v_ma := public._agenda_local_modo('acesso');
  v_mp := public._agenda_local_modo('patio');
  v_mv := public._agenda_local_modo('viagem');
  v_modos := array[v_mc, v_ma, public._agenda_local_modo('bem'), v_mp, v_mv, public._agenda_local_modo('mesmo_local')];
  if 'sombra' <> all (v_modos) and 'ligado' <> all (v_modos) then
    return jsonb_build_object('ok', true, 'texto', 'Os locais ainda estão desligados na agenda.', 'linhas', '[]'::jsonb, 'cadastro', '{}'::jsonb, 'em_teste', '[]'::jsonb);
  end if;

  -- ── o foco por OS: o texto longo, só da p_os ──
  v_ate := p_hoje + 7 * c_semanas;
  for r in select p_os as os where p_os is not null loop
    v_b := public._agenda_local_bloco(r.os, p_hoje);
    continue when v_b is null;
    v_rot := public._agenda_rotulo_da_os(r.os);
    v_lig := array(select c ->> 'texto' from jsonb_array_elements(v_b -> 'combinar') with ordinality t(c, o) where not (c ->> 'em_teste')::boolean order by o);
    v_tes := array(select c ->> 'texto' from jsonb_array_elements(v_b -> 'combinar') with ordinality t(c, o) where (c ->> 'em_teste')::boolean order by o);
    v_linha := concat_ws(' ', format('%s: %s.', v_rot, v_b ->> 'texto'), v_b ->> 'bem_texto', v_b ->> 'perguntei', v_b ->> 'viagem_texto',
                         case when cardinality(v_lig) > 0 then 'Combinar: ' || array_to_string(v_lig, '; ') || '.' end,
                         case when cardinality(v_tes) > 0 then 'Em teste, eu cobraria: ' || array_to_string(v_tes, '; ') || '.' end);
    -- As notas por último, inteiras, só as que cabem: o que falta combinar nunca sai por causa delas
    for v_n in select x from jsonb_array_elements_text(v_b -> 'notas') with ordinality t(x, o) order by o loop
      if char_length(v_linha) + 1 + char_length(v_n) <= c_linha then
        v_linha := v_linha || ' ' || v_n;
      end if;
    end loop;
    v_linha := public._agenda_corta(v_linha, c_linha - 1);   -- o "…" conta nas 400
    v_l := v_l || (case when p_os is null then '- ' else '' end || v_linha);
    v_lin := v_lin || jsonb_build_object('os', r.os, 'rotulo', v_rot, 'local', v_b, 'texto', v_linha);
    if v_mp <> 'desligado' and v_b ->> 'tipo' like 'patio\_%' and v_b -> 'vagas' = 'null'::jsonb then
      v_pn := v_pn + 1;
      v_pnome := v_b ->> 'nome';
    end if;
  end loop;

  -- FASE 7d: (correção O1; decisão do fio, vale sobre a §5.8) o foco geral: TODAS as OS abertas, com plano ou sem, porque são as sem plano e as supostas que o dono precisa corrigir. Uma
  -- linha curta por OS (nome, OS, lugar, fonte), lida pela cadeia _agenda_local_resolvido, que vale em todo modo; as suposicoes da proposta só existem com os modos ligados. Primeiro as
  -- que estou supondo ou não sei, depois as ditas. O texto longo e o que combinar ficam no foco por OS.
  for r in
    select k.service_order_id as os, public._agenda_rotulo_da_os(k.service_order_id) as rot, x.ini
      from public.os_carteira(p_hoje) k
      left join lateral (select min(a.dia) as ini from public.agenda_alocacoes a
                          where a.service_order_id = k.service_order_id and a.estado in ('publicada', 'fixada') and a.dia between p_hoje and v_ate) x on true
     where p_os is null
     order by x.ini nulls last, 2, 1
  loop
    v_lr := public._agenda_local_resolvido(r.os, p_hoje);
    continue when v_lr is null;
    v_por := case when coalesce((v_lr ->> 'suposicao')::boolean, false) then 'suposição' else substring(v_lr ->> 'texto' from '\(([^()]*)\)$') end;
    v_lugar := case when v_lr ->> 'fonte' = 'nenhum' then v_lr ->> 'texto'
                    when v_lr ->> 'tipo' = 'casa_cliente' then v_lr ->> 'texto'
                    when v_lr ->> 'fonte' = 'cidade' then format('%s (%s)', v_lr ->> 'texto_curto', v_por)
                    else format('%s (%s)', v_lr ->> 'nome', v_por) end;
    v_linha := format('- %s: %s.', r.rot, v_lugar);
    if coalesce((v_lr ->> 'suposicao')::boolean, false) or v_lr ->> 'fonte' = 'nenhum' then
      v_sup := v_sup || v_linha;
    else
      v_dit := v_dit || v_linha;
    end if;
    v_lin := v_lin || jsonb_build_object('os', r.os, 'rotulo', r.rot, 'texto', ltrim(v_linha, '- '),
                                         'local', jsonb_build_object('texto', v_lr ->> 'texto', 'fonte', v_lr ->> 'fonte', 'suposicao', v_lr -> 'suposicao',
                                                                     'tipo', v_lr ->> 'tipo', 'nome', v_lr ->> 'nome'));
    if v_mp <> 'desligado' and r.ini is not null and v_lr ->> 'tipo' like 'patio\_%'
       and (select l.vagas from public.agenda_locais l where l.id = (v_lr ->> 'local_id')::uuid) is null then
      v_pn := v_pn + 1;
      v_pnome := v_lr ->> 'nome';
    end if;
  end loop;
  -- FASE 7d: fim

  -- ── quem ficou de fora porque o pátio encheu: a última montagem que citou a OS (só com modo_patio ligado: o motor só diz isso ligado) ──
  if v_mp = 'ligado' then
    v_fora := array(
      select '- ' || (z.f ->> 'texto')
        from (select distinct on (y.os) y.f, y.criada_em, y.os
                from (select (f ->> 'os')::uuid as os, f, pr.criada_em, pr.id
                        from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
                      union all
                      select (i ->> 'os')::uuid, null::jsonb, pr.criada_em, pr.id
                        from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.itens, '[]'::jsonb)) i) y
               where (y.criada_em at time zone 'America/Sao_Paulo')::date <= p_hoje
                 and y.os in (select k.service_order_id from public.os_carteira(p_hoje) k where p_os is null or k.service_order_id = p_os)
               order by y.os, y.criada_em desc, y.id desc) z
       where coalesce((z.f ->> 'patio_cheio')::boolean, false)
       order by z.criada_em, z.os);
  end if;

  -- ── o cadastro ──
  select count(*)::int into v_total from public.agenda_locais l where l.ativo and l.tipo <> 'casa_cliente';   -- (correção O3) a casa é de um cliente, não do cadastro
  v_dono := array(select format('%s, em %s', l.nome, to_char(l.conferido_em, 'DD/MM'))
                    from public.agenda_locais l
                   where l.ativo and l.conferido_por = 'dono' and public._agenda_local_conferido(l.id, p_hoje)
                   order by l.conferido_em desc, l.nome);
  select count(*)::int into v_mar from public.agenda_locais l where l.ativo and l.conferido_por = 'marina' and public._agenda_local_conferido(l.id, p_hoje);
  v_notas := array(
    select format('%s %s (%s)', y.nome, public._agenda_lista(y.f, null), case when y.conferido_por = 'pesquisa' then 'pesquisa' else 'a conferir de novo' end)
      from (select l.nome, l.conferido_por, l.conferido_em,
                   array_remove(array[case when l.exige_autorizacao then 'pede autorização' end,
                                      case when l.seguro_exigido then 'pede seguro' end,
                                      case l.sabado when 'nao' then 'não abre no sábado' when 'manha' then 'no sábado só abre de manhã' when 'dia' then 'abre no sábado' end,
                                      case when l.tem_garagem_seca then 'tem garagem seca' end], null) as f
              from public.agenda_locais l
             where l.ativo and l.conferido_por is not null and not public._agenda_local_conferido(l.id, p_hoje)) y
     where cardinality(y.f) > 0
     order by y.conferido_em desc, y.nome);
  v_cad := format('Locais: %s no cadastro; ', v_total)
           || case cardinality(v_dono) when 0 then 'nenhum conferido por você'
                when 1 then format('1 conferido por você (%s)', v_dono[1])
                else format('%s conferidos por você (%s%s)', cardinality(v_dono), array_to_string(v_dono[1:c_nomes], '; '),
                            case when cardinality(v_dono) > c_nomes then format('; e mais %s', cardinality(v_dono) - c_nomes) else '' end) end
           || case when v_mar > 0 then format(', %s pela marina', v_mar) else '' end || '.';
  -- (correção O1) as notas entram no corte, no fim: são as primeiras a sair
  v_nn := least(cardinality(v_notas), c_nomes);
  -- FASE 7d: (correção C9; §11 "Parar") o dono desfez 2 gravações do mesmo local em 4 semanas: o apelido ou a leitura está errado. Só recomenda: a decisão é dele
  if p_os is null then
    v_apelido := array(
      select format('%s: você desfez %s gravações desse local em %s semanas. Recomendo tirar o apelido; a decisão é sua.', l.nome, count(*), c_parar_dias / 7)
        from public.agenda_acoes a
        join public.agenda_locais l on l.id = (a.depois ->> 'local_id')::uuid
       where a.tipo = 'local' and a.desfeita_em is not null and (a.desfeita_em at time zone 'America/Sao_Paulo')::date > p_hoje - c_parar_dias
         and cardinality(l.apelidos) > 0
       group by l.id, l.nome
      having count(*) >= c_parar_vezes
       order by l.nome);
  end if;
  -- FASE 7d: fim
  v_cadj := jsonb_build_object('locais', v_total, 'conferidos', cardinality(v_dono) + v_mar, 'nomes', to_jsonb(v_dono), 'notas', to_jsonb(v_notas));
  if v_pn > 0 then
    v_pat := format('%s: %s nas próximas %s semanas (sem número de vagas, só conto).', v_pnome, public._agenda_plural(v_pn, 'serviço', 'serviços'), c_semanas);
  end if;

  -- ── o que eu faria com os modos ligados ──
  if 'sombra' = any (array[v_mc, v_ma, v_mp, v_mv]) then
    for e in select x from jsonb_array_elements(public._agenda_local_conflitos(p_hoje)) with ordinality t(x, o) order by o loop
      continue when p_os is not null and (e ->> 'os')::uuid is distinct from p_os;
      v_rot := public._agenda_rotulo_da_os((e ->> 'os')::uuid);
      v_nome := split_part(v_rot, ' (', 1);
      -- o motivo sem o dia: "ter 20/07 é feriado em X", "sáb 24/07: X não abre no sábado", "ter 20/07 de manhã: X não recebe a equipe"
      v_resto := regexp_replace(e ->> 'motivo', '^.*?(: | é )', '');
      if e ->> 'tipo' = 'calendario' and v_mc = 'sombra' and (e ->> 'origem' = 'mascara' or v_mp <> 'desligado') then
        v_teste := v_teste || format('Em teste: com o calendário do local ligado, eu não marcaria %s para %s (%s).',
                                     case when e ->> 'turno' is not null then public._agenda_meio_texto((e ->> 'dia')::date, e ->> 'turno')
                                          else public._dia_curto((e ->> 'dia')::date) end, v_nome, v_resto);
      elsif e ->> 'tipo' = 'acesso' and v_ma = 'sombra' then
        v_teste := v_teste || format('Em teste: eu perguntaria a você hoje sobre %s: %s.', v_rot, e ->> 'motivo');
      elsif e ->> 'tipo' = 'patio' and v_mp = 'sombra' then
        v_teste := v_teste || format('Em teste: com o pátio ligado, eu não marcaria %s para %s: %s.', public._dia_curto((e ->> 'dia')::date), v_nome, v_resto);
      elsif e ->> 'tipo' = 'viagem' and v_mv = 'sombra' then
        v_teste := v_teste || format('Em teste: com a viagem ligada, eu remarcaria %s: %s.', v_rot, e ->> 'motivo');
      end if;
    end loop;
  end if;

  -- O que vem depois das linhas das OS. O corte tira as linhas de OS do fim ("- e mais N serviços."): o cadastro e o "Em teste" ficam; só depois, o corte de sempre (_agenda_juntar).
  v_rodape := v_teste[1:c_teste];
  if cardinality(v_teste) > c_teste then
    v_rodape := v_rodape || format('Em teste: e mais %s.', cardinality(v_teste) - c_teste);
  end if;
  if p_os is not null then
    v_final := v_l || v_fora || v_rodape;
  -- FASE 7d: (correção O1) o teto: cortam primeiro as notas dos locais, depois as ditas, e por último as supostas, sempre com "(e mais N)". O resto do foco fica
  else
    v_cab := 'Onde é cada serviço:';
    loop
      v_final := case when cardinality(v_sup) + cardinality(v_dit) = 0 then array['Nenhum serviço em aberto.']
                      else array[v_cab] end
                 || case when cardinality(v_sup) > 0 then array['Estou supondo ou não sei (me corrija):'] else '{}'::text[] end
                 || v_sup[1:cardinality(v_sup) - v_cs]
                 || case when v_cs > 0 then array[format('(e mais %s)', v_cs)] else '{}'::text[] end
                 || case when cardinality(v_dit) > 0 then array['Já ditos:'] else '{}'::text[] end
                 || v_dit[1:cardinality(v_dit) - v_cd]
                 || case when v_cd > 0 then array[format('(e mais %s)', v_cd)] else '{}'::text[] end
                 || v_fora
                 || (v_cad || case when cardinality(v_notas) = 0 then ''
                                   when v_nn = cardinality(v_notas) then ' Só como nota: ' || array_to_string(v_notas[1:v_nn], '; ') || '.'
                                   else ' Só como nota: ' || coalesce(array_to_string(v_notas[1:v_nn], '; ') || ' ', '') || format('(e mais %s).', cardinality(v_notas) - v_nn) end)
                 || coalesce(v_pat, '')
                 || v_apelido
                 || v_rodape;
      exit when char_length(array_to_string(v_final, E'\n')) <= cf.texto_max;
      if v_nn > 0 then
        v_nn := v_nn - 1;
      elsif v_cd < cardinality(v_dit) then
        v_cd := v_cd + 1;
      elsif v_cs < cardinality(v_sup) then
        v_cs := v_cs + 1;
      else
        exit;
      end if;
    end loop;
  -- FASE 7d: fim
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_final, cf.texto_max), 'linhas', v_lin, 'cadastro', v_cadj, 'em_teste', to_jsonb(v_teste));
end;
$function$;
comment on function public._agenda_ver_locais(date, uuid) is
  'Agenda de Produção (Fase 7d, P8; §5.8, §6.2; R6.3-12): o foco locais de agenda_ver (*agenda locais*). "Onde é cada serviço (próximas 3 semanas):", uma linha por OS da carteira com plano ou reserva nessas semanas, a que começa primeiro antes (até 400 letras, de _agenda_local_bloco: o local e a fonte, o bem, "Perguntei ao cliente em 15/07." só com o M11 que saiu, a viagem fora da região, "Combinar: …" do que tem o modo ligado, "Em teste, eu cobraria: …" do que está em teste, e as notas que couberem); quem ficou de fora porque o pátio encheu (modo_patio ligado); o cadastro ("Locais: 6 no cadastro; 1 conferido por você (Marina Itajaí, em 01/07). Só como nota: …"); sem vagas ditas, quantos serviços no pátio (só conta); e, com algum modo em teste, o que eu faria (_agenda_local_conflitos: "Em teste: com o calendário do local ligado, eu não marcaria ter 20/07 para Lenine (feriado em Balneário Camboriú)."), até 3 no texto. Sem nada: "Nenhum serviço marcado nas próximas 3 semanas. Locais: …". Com p_os, só a OS, sem o cadastro. Com os 6 modos desligados, "Os locais ainda estão desligados na agenda.". {ok, texto (até texto_max), linhas [{os, rotulo, local, texto}], cadastro {locais, conferidos, nomes, notas}, em_teste []}. Só lê. STABLE; definer (o combinar e os conflitos são só do service_role), com a porta dentro (com login, só admin/financeiro: 42501; sem login, só o service_role); authenticated e service_role (agenda_ver, invoker, a chama). Correção da 7d (O1, decisão do fio, vale sobre a §5.8): o foco geral mostra TODAS as OS abertas, uma linha curta por OS, pela cadeia _agenda_local_resolvido, primeiro as que estou supondo ou não sei; no teto, cortam as notas, as ditas e por último as supostas, com "(e mais N)". O texto longo fica no foco por OS. C9: a recomendação de tirar o apelido.';

create or replace function public.agenda_rascunho_aplicar(p_autor uuid, p_canal text, p_proposta text default null,
                                                          p_os text[] default null, p_decisao text default null,
                                                          p_opcao text default null, p_trecho text default null,
                                                          p_hoje date default public._hoje_brt(),
                                                          p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_rec    jsonb := public._agenda_pedido_recusa(p_canal, p_trecho, 'agenda_rascunho_aplicar');
  cf       public.agenda_config := public._agenda_cfg();
  v_lista  jsonb;
  v_q      jsonb;
  v_qs     jsonb;
  v_opc    jsonb;
  v_opcs   jsonb;
  v_ro     jsonb;
  v_n      int;
  v_ref    text;
  v_sim    jsonb;
  v_mud    text;
  v_p      public.agenda_propostas%rowtype;
  v_os     uuid[];
  v_x      text;
  v_viol   jsonb;
  v_sel    jsonb;
  v_frase  text;
  v_txt    text;
  -- FASE 7d: (7d P6b) as perguntas com opções e sem número, se mais de uma espera, a pergunta "qual?" e a linha da pergunta escolhida
  v_7d_fora   jsonb;
  v_7d_varias boolean;
  v_7d_qual   text;
  v_7d_linha  public.agenda_perguntas%rowtype;
  -- FASE 7d: fim
  v_ncanc  int;
begin
  if v_rec is not null then
    return v_rec;
  end if;
  if p_decisao is not null and p_proposta is not null then
    raise exception 'agenda_rascunho_aplicar: diga a proposta OU a decisão, não as duas' using errcode = '22023';
  end if;

  -- ── Responder uma decisão crítica ──
  if nullif(btrim(coalesce(p_decisao, '')), '') is not null or nullif(btrim(coalesce(p_opcao, '')), '') is not null then
    v_lista := public.agenda_decisoes_abertas(p_agora);
    -- FASE 7d: (7d P6b) quem também espera o dono sem ter número: tem opções, mas agenda_decidir não sabe o que fazer com elas (a nota e o aviso do fornecedor, que se
    -- respondem por material_informar) ou ele já escolheu "eu digo". "1" pode ser para ela: com mais de uma esperando, ninguém escolhe por ele.
    v_7d_fora := coalesce((select jsonb_agg(p.texto order by p.perda_em nulls last, p.criada_em, p.id)
                             from public.agenda_perguntas p
                            where p.estado = 'aberta' and p.modo = 'ligado'
                              and (p.expira_em is null or p.expira_em > p_agora)
                              and case when jsonb_typeof(p.opcoes) = 'array' then jsonb_array_length(p.opcoes) > 0 else false end
                              and not exists (select 1 from jsonb_array_elements(v_lista) e where e ->> 'id' = p.id::text)), '[]'::jsonb);
    if jsonb_array_length(v_lista) = 0 and jsonb_array_length(v_7d_fora) > 0 then
      return public._agenda_recusa('Essa pergunta não tem número de decisão: me responda com as suas palavras. '
        || (select string_agg(x, ' ') from jsonb_array_elements_text(v_7d_fora) x), 'sem_numero');
    end if;
    v_7d_varias := jsonb_array_length(v_lista) + jsonb_array_length(v_7d_fora) > 1;
    v_7d_qual := format('Qual decisão? %s. Diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.',
                        (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
                           from jsonb_array_elements(v_lista) q))
                 || coalesce(' Sem número, responda com as suas palavras: '
                             || (select string_agg(x, ' ') from jsonb_array_elements_text(v_7d_fora) x), '');
    -- FASE 7d: fim
    if jsonb_array_length(v_lista) = 0 then
      return public._agenda_recusa('Não tenho decisão da agenda esperando você agora.', 'sem_decisao');
    end if;
    v_ref := btrim(coalesce(p_decisao, ''));
    if v_ref ~ '^\d{1,3}$' then
      select q into v_q from jsonb_array_elements(v_lista) q where (q ->> 'n')::int = v_ref::int;
      if v_q is null then
        return public._agenda_recusa(format('Não tenho a decisão %s. As que esperam você: %s.', v_ref,
          (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
             from jsonb_array_elements(v_lista) q)), 'decisao_nao_existe');
      end if;
    elsif v_ref <> '' then
      v_ro := public.agenda_resolver_os(v_ref, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      select coalesce(jsonb_agg(q order by (q ->> 'n')::int), '[]'::jsonb) into v_qs
        from jsonb_array_elements(v_lista) q
       where q ->> 'os' = v_ro ->> 'id' or (q -> 'os_ids') ? (v_ro ->> 'id');
      if jsonb_array_length(v_qs) = 0 then
        return public._agenda_recusa(format('Não tenho decisão esperando você sobre %s.', v_ro ->> 'cliente_curto'), 'decisao_nao_existe');
      end if;
      if jsonb_array_length(v_qs) > 1 then
        return public._agenda_recusa(format('Qual delas? %s.',
          (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
             from jsonb_array_elements(v_qs) q)), 'decisao_ambigua');
      end if;
      v_q := v_qs -> 0;
    -- FASE 7d: (7d P6b) sem dizer qual: com a lista de uma só, mas outra pergunta com opções esperando, também pergunta qual
    elsif v_7d_varias then
      return public._agenda_recusa(v_7d_qual, 'decisao_ambigua');
    -- FASE 7d: fim
    elsif jsonb_array_length(v_lista) = 1 then
      v_q := v_lista -> 0;
    else
      return public._agenda_recusa(format('Qual decisão? %s.',
        (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
           from jsonb_array_elements(v_lista) q)), 'decisao_ambigua');
    end if;

    -- FASE 7d: (7d P8; os evals S24 e K57) a resposta em palavras: "lança meia pro Roberto" e "na decisão do aviso do Nelson, pode mandar" são respostas, e o modelo achou os números
    -- pela lista, como o prompt manda. A régua abaixo é para o número solto: quando as palavras dele identificam a pergunta e falam da opção, ela não se aplica. "pode ser" não diz nada, e continua perguntando.
    if v_7d_varias and btrim(coalesce(p_opcao, '')) ~ '^\d{1,2}$'
       and public._agenda_disse_em_palavras(p_trecho, v_q ->> 'texto',
             (select o ->> 'texto' from jsonb_array_elements(v_q -> 'opcoes') o where (o ->> 'n')::int = btrim(p_opcao)::int),
             array(select q ->> 'texto' from jsonb_array_elements(v_lista) q where q ->> 'id' <> v_q ->> 'id')
             || array(select x from jsonb_array_elements_text(v_7d_fora) x)) then
      v_7d_varias := false;
    end if;
    -- FASE 7d: fim
    -- FASE 7d: (7d P6b) com mais de uma esperando, a decisão e a opção têm de estar nas palavras do dono: "1" sozinho não é a decisão 1, opção 1, e a decisão pelo nome só
    -- vale com o nome dito. A opção pelo nome da OS ("pode atrasar o Nelson") não passa aqui: ela mesma diz qual.
    if v_7d_varias and btrim(coalesce(p_opcao, '')) ~ '^\d{1,2}$'
       and not (case when v_ref ~ '^\d{1,3}$' then public._agenda_disse_os_numeros(p_trecho, v_ref::int, btrim(p_opcao)::int)
                     else exists (select 1 from regexp_split_to_table(public._agenda_normal(v_ref), ' ') w
                                   where char_length(w) >= 3
                                     and public._agenda_normal(p_trecho) ~ ('(^| )' || w || '( |$)'))
                          and public._agenda_disse_os_numeros(p_trecho, null, btrim(p_opcao)::int) end) then
      return public._agenda_recusa(v_7d_qual, 'decisao_ambigua');
    end if;
    -- FASE 7d: fim
    -- A opção: o nº ou o nome da OS que aceita atrasar. Sem ela, a pergunta volta como está (o banco não escolhe).
    v_ref := btrim(coalesce(p_opcao, ''));
    if v_ref = '' then
      return public._agenda_recusa(rtrim(v_q ->> 'texto', ' ')
        || case when (v_q ->> 'texto') ~ '\d\)' then '' else ' ' || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; '
                                                                   order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o) end,
        'sem_opcao',
        (select jsonb_agg((o ->> 'n') || ') ' || (o ->> 'texto') order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o));
    end if;
    if v_ref ~ '^\d{1,2}$' then
      select o into v_opc from jsonb_array_elements(v_q -> 'opcoes') o where (o ->> 'n')::int = v_ref::int;
    else
      v_ro := public.agenda_resolver_os(v_ref, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      select coalesce(jsonb_agg(o order by (o ->> 'n')::int), '[]'::jsonb) into v_opcs
        from jsonb_array_elements(v_q -> 'opcoes') o where o ->> 'os' = v_ro ->> 'id';
      if jsonb_array_length(v_opcs) > 1 then
        return public._agenda_recusa(format('Qual das opções? %s',
          (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
             from jsonb_array_elements(v_opcs) o)) || '.', 'opcao_ambigua');
      end if;
      v_opc := v_opcs -> 0;
    end if;
    if v_opc is null then
      return public._agenda_recusa('Essa opção não existe. As opções são: '
        || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
              from jsonb_array_elements(v_q -> 'opcoes') o) || '.', 'opcao_nao_existe',
        (select jsonb_agg((o ->> 'n') || ') ' || (o ->> 'texto') order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o));
    end if;

    -- FASE 7d: (7d P6b, R6.7b) a não crítica cujo modo não vale agora: agenda_decidir recusaria no *grava*, e a frase seria "a agenda mudou". Com o freio, as do gestor têm
    -- número e não têm resposta, como sempre foi: nenhum caminho novo marca dia.
    select p.* into v_7d_linha from public.agenda_perguntas p where p.id = (v_q ->> 'id')::uuid;
    if not v_7d_linha.critica and coalesce(public._agenda_modo_da_pergunta(v_7d_linha.tipo, v_7d_linha.chave), 'desligado') <> 'ligado' then
      return public._agenda_recusa(
        case when cf.gestor_so_propor and v_7d_linha.tipo in ('situacao', 'estimativa', 'reavaliar', 'reestimar')
             then 'Com *gestor, só propor* essa resposta não muda nada agora. Se quiser, me diga com as suas palavras (por exemplo, os dias do serviço).'
             else 'Essa pergunta ainda está em teste: mostro como ficaria, mas não mudo nada.' end, 'em_teste');
    end if;
    -- FASE 7d: fim
    -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
    -- volta com os dias de agora (a mesma régua do agenda_decidir).
    if (v_q ->> 'versao_base')::bigint is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
       and v_opc -> 'espera' <> '{}'::jsonb then
      v_sim := public.agenda_propor('replano', null, null, array(select x::uuid from jsonb_array_elements_text(v_q -> 'os_ids') x),
                                    coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb), false, 'dono', v_autor, p_hoje, p_agora);
      select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                               coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
        into v_mud
        from jsonb_each(v_opc -> 'espera') e
        left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                            where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
       where x.fim is distinct from (e.value #>> '{}')::date;
      if v_mud is not null then
        return public._agenda_recusa('A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.',
                                     'decisao_mudou');
      end if;
    end if;

    -- FASE 7d: (7d P6b; correção O18) a releitura diz de qual pergunta é a opção: "Está combinado" sozinho não diz nada, e o *grava* é o único portão. Vale para a crítica também: com 2
    -- perguntas da mesma OS abertas, ele conferia às cegas. O caminho de baixo, o de antes, não roda mais; fica para os tiradores das etapas anteriores.
    if true then
      v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'aplicar', 'decisao:' || (v_q ->> 'id'),
                 nullif(v_q ->> 'os', '')::uuid,
                 jsonb_build_object('grupo', 'decisao:' || (v_q ->> 'id'), 'rotulo_grupo', 'Decisão', 'pergunta_id', v_q ->> 'id',
                                    'opcao', (v_opc ->> 'n')::int, 'opcao_texto', v_opc ->> 'texto',
                                    'frase_pronta', format('na pergunta "%s": %s', public._agenda_corta(v_7d_linha.texto, 90), rtrim(v_opc ->> 'texto', '.'))),
                 p_trecho, p_hoje);
      return jsonb_build_object('ok', true, 'item', v_txt,
                                'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
    end if;
    -- FASE 7d: fim
    v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'aplicar', 'decisao:' || (v_q ->> 'id'),
               nullif(v_q ->> 'os', '')::uuid,
               jsonb_build_object('grupo', 'decisao:' || (v_q ->> 'id'), 'rotulo_grupo', 'Decisão', 'pergunta_id', v_q ->> 'id',
                                  'opcao', (v_opc ->> 'n')::int, 'opcao_texto', v_opc ->> 'texto',
                                  'frase_pronta', rtrim(v_opc ->> 'texto', '.')),
               p_trecho, p_hoje);
    return jsonb_build_object('ok', true, 'item', v_txt,
                              'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
  end if;

  -- ── Publicar uma proposta aberta ──
  v_lista := public.agenda_propostas_abertas(p_agora);
  if jsonb_array_length(v_lista) = 0 then
    return public._agenda_recusa('Não tenho plano montado para publicar. Peça para eu montar (por exemplo, "monta a semana que vem").',
                                 'sem_proposta');
  end if;
  v_ref := public._agenda_normal(p_proposta);
  v_n := case when v_ref in ('', 'a ultima', 'ultima', 'essa', 'esta', 'a proposta', 'proposta', 'ela', 'isso', 'a semana', 'semana')
              then 1
              when v_ref ~ '^\d{1,3}$' then v_ref::int end;
  if v_n is null then
    return public._agenda_recusa(format('Qual plano? %s.',
      (select string_agg((p ->> 'n') || ') ' || coalesce(p ->> 'titulo', 'plano'), '; ' order by (p ->> 'n')::int)
         from jsonb_array_elements(v_lista) p)), 'proposta_ambigua');
  end if;
  select pr.* into v_p from public.agenda_propostas pr
   where pr.id = (select (p ->> 'id')::uuid from jsonb_array_elements(v_lista) p where (p ->> 'n')::int = v_n);
  if not found then
    return public._agenda_recusa(format('Não tenho o plano %s montado.', v_n), 'proposta_nao_existe');
  end if;
  if v_p.versao_base <> cf.versao_plano then
    return public._agenda_recusa('A agenda mudou desde que eu montei: peça de novo que eu refaço.', 'proposta_obsoleta');
  end if;

  -- só as OS ditas ("publica só o Lenine e o Flávio"), e só se estão na proposta
  if p_os is not null and cardinality(p_os) > 0 then
    v_os := '{}';
    foreach v_x in array p_os loop
      v_ro := public.agenda_resolver_os(v_x, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      if not exists (select 1 from jsonb_array_elements(v_p.itens) i where i ->> 'os' = v_ro ->> 'id') then
        return public._agenda_recusa(format('%s não está nesse plano.', v_ro ->> 'cliente_curto'), 'os_fora_da_proposta');
      end if;
      v_os := v_os || (v_ro ->> 'id')::uuid;
    end loop;
    v_os := array(select distinct x from unnest(v_os) x order by 1);
  end if;

  v_viol := public.agenda_validar(v_p.id, v_os, p_hoje, p_agora);
  if jsonb_array_length(v_viol) > 0 then
    return public._agenda_recusa('Não dá para publicar: '
      || (select string_agg(e ->> 'texto', ' ' order by o) from jsonb_array_elements(v_viol) with ordinality t(e, o)), 'proposta_invalida');
  end if;
  v_sel := public._agenda_itens_escolhidos(v_p.itens, v_os, null);
  if not exists (select 1 from jsonb_array_elements(v_sel) i where i ->> 'op' = 'criar') and jsonb_array_length(v_sel) = 0 then
    return public._agenda_recusa('No plano que eu montei não há nada para publicar sem a sua decisão: veja o que a agenda precisa de você.',
                                 'so_critico');
  end if;
  v_ncanc := (select count(*) from jsonb_array_elements(v_sel) i where i ->> 'op' = 'cancelar');
  v_frase := case when v_p.escopo = 'semana'
                  then lower(left(coalesce(v_p.textos ->> 'titulo', 'a semana'), 1)) || substr(coalesce(v_p.textos ->> 'titulo', 'a semana'), 2) || ': '
                  else '' end
             || coalesce(nullif(array_to_string(array(
                  select regexp_replace(rtrim(i ->> 'texto', '.'), '^([^:]*): ', '\1, ')
                    from jsonb_array_elements(v_sel) with ordinality t(i, k)
                   where i ->> 'op' = 'criar'
                   order by (i ->> 'de')::date, i ->> 'numero' collate "C", k), '; '), ''), 'nada novo')
             || case when v_ncanc > 0 then format('; e tiro da agenda %s que não pode mais acontecer',
                                                   public._agenda_plural(v_ncanc, 'serviço', 'serviços')) else '' end;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'aplicar', 'aplicar:' || v_p.id::text, null,
             jsonb_build_object('grupo', 'aplicar:' || v_p.id::text, 'rotulo_grupo', 'Publico na agenda', 'proposta_id', v_p.id,
                                'os_ids', to_jsonb(v_os), 'frase_pronta', v_frase),
             p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

-- ── As portas das novas: internas, de ninguém; quem as chama é definer ──
revoke all on function public._agenda_data_sem_mes(text), public._agenda_local_novo(text), public._agenda_municipio_conhecido(text, uuid),
                       public._agenda_local_criar(text, text, text, uuid), public._agenda_local_da_casa(uuid, uuid),
                       public._agenda_feriado_do_bloco(jsonb, date, date, date), public._agenda_local_avisar_acesso(date, timestamptz)
  from public, anon, authenticated, service_role;
